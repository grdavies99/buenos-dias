sub init()
    m.top.functionName = "mdnsResponder_run"
end sub

sub mdnsResponder_run()
    service = mdnsResponder_config()
    if service = invalid then return

    port = CreateObject("roMessagePort")
    socket = mdns_openSocket(port)
    if socket = invalid
        m.top.error = "could not bind mDNS port 5353"
        return
    end if
    m.top.observeField("control", port)

    buffer = CreateObject("roByteArray")
    bufferSize = mdns_constants().bufferSize
    buffer[bufferSize - 1] = 0

    ' RFC 6762 8.3: at least two announcements, one second apart
    mdnsResponder_announce(socket, service, service.ttl)
    m.top.advertising = true
    announceDelay = 1000
    clock = CreateObject("roTimespan")

    while true
        timeout = 0
        if announceDelay > 0
            timeout = announceDelay - clock.TotalMilliseconds()
            if timeout < 1 then timeout = 1
        end if
        event = wait(timeout, port)

        if event = invalid
            mdnsResponder_announce(socket, service, service.ttl)
            announceDelay = service.reannounceMs
            clock.Mark()
        else if type(event) = "roSGNodeEvent"
            if event.getField() = "control" and LCase(event.getData()) = "stop" then exit while
        else if type(event) = "roSocketEvent"
            if socket.isReadable()
                received = socket.receive(buffer, 0, bufferSize)
                if received > 0
                    try
                        query = mdns_parseMessage(buffer, received)
                        if query <> invalid and not query.isResponse
                            response = mdnsResponder_answer(service, query)
                            if response <> invalid then socket.send(response, 0, response.count())
                        end if
                    catch e
                        ' the group carries every device's traffic - never let a bad packet kill the responder
                        print "MdnsResponder: ignoring unparseable packet: "; e.message
                    end try
                end if
            end if
            if not socket.eOK() then exit while
        end if
    end while

    ' RFC 6762 10.1: goodbye packet so peers drop us immediately
    mdnsResponder_announce(socket, service, 0)
    socket.close()
    m.top.advertising = false
end sub

function mdnsResponder_config() as dynamic
    if m.top.serviceType = ""
        m.top.error = "serviceType is required"
        return invalid
    end if
    if m.top.port <= 0
        m.top.error = "port is required"
        return invalid
    end if

    instanceName = m.top.instanceName
    if instanceName = "" then instanceName = CreateObject("roDeviceInfo").GetFriendlyName()
    instanceName = instanceName.replace(".", " ")

    hostName = m.top.hostName
    if hostName = "" then hostName = CreateObject("roRegex", "[^A-Za-z0-9-]+", "").replaceAll(instanceName, "-")
    hostName = mdns_fqdn(hostName)

    ttl = m.top.ttl
    if ttl <= 0 then ttl = 4500

    serviceType = mdns_fqdn(m.top.serviceType)
    return {
        serviceType: serviceType
        instanceName: instanceName
        fullName: instanceName + "." + serviceType
        hostName: hostName
        port: m.top.port
        fixedIp: m.top.ipAddress
        ip: ""
        txt: m.top.txt
        ttl: ttl
        reannounceMs: m.top.reannounceInterval * 1000
    }
end function

' Re-reads the address so DHCP lease changes are picked up. Returns false if there is none.
function mdnsResponder_refreshIp(service as object) as boolean
    if service.fixedIp <> ""
        service.ip = service.fixedIp
    else
        ip = mdns_localIPv4()
        if ip = invalid then return false
        service.ip = ip
    end if
    return true
end function

sub mdnsResponder_announce(socket as object, service as object, ttl as integer)
    if not mdnsResponder_refreshIp(service)
        print "MdnsResponder: no IPv4 address, skipping announcement"
        return
    end if
    r = mdnsResponder_records(service, ttl)
    packet = mdns_buildResponse([r.ptr, r.srv, r.txt, r.a, r.meta], [r.nsec])
    socket.send(packet, 0, packet.count())
end sub

function mdnsResponder_records(service as object, ttl as integer) as object
    c = mdns_constants()
    hostTtl = ttl
    if hostTtl > 120 then hostTtl = 120
    return {
        ptr: { name: service.serviceType, type: c.typePTR, ttl: ttl, cacheFlush: false, data: service.fullName }
        meta: { name: c.metaQueryName, type: c.typePTR, ttl: ttl, cacheFlush: false, data: service.serviceType }
        srv: { name: service.fullName, type: c.typeSRV, ttl: hostTtl, cacheFlush: true, data: { priority: 0, weight: 0, port: service.port, target: service.hostName } }
        txt: { name: service.fullName, type: c.typeTXT, ttl: ttl, cacheFlush: true, data: service.txt }
        a: { name: service.hostName, type: c.typeA, ttl: hostTtl, cacheFlush: true, data: service.ip }
        ' asserts we have no AAAA for the host (RFC 6762 6.1)
        nsec: { name: service.hostName, type: c.typeNSEC, ttl: hostTtl, cacheFlush: true, data: { nextDomain: service.hostName, types: [c.typeA] } }
    }
end function

' Builds a response for the questions in `query` that are about us, or invalid if none are.
function mdnsResponder_answer(service as object, query as object) as dynamic
    c = mdns_constants()
    if not mdnsResponder_refreshIp(service) then return invalid
    r = mdnsResponder_records(service, service.ttl)
    serviceType = LCase(service.serviceType)
    fullName = LCase(service.fullName)
    hostName = LCase(service.hostName)

    answers = []
    additionals = []
    seen = {}
    for each q in query.questions
        name = LCase(q.name)
        isAny = q.type = c.typeANY
        if name = serviceType and (q.type = c.typePTR or isAny)
            if not mdnsResponder_knownAnswer(query, service)
                mdnsResponder_add(answers, seen, r.ptr)
                additionals.append([r.srv, r.txt, r.a, r.nsec])
            end if
        else if name = LCase(c.metaQueryName) and (q.type = c.typePTR or isAny)
            mdnsResponder_add(answers, seen, r.meta)
        else if name = fullName
            if q.type = c.typeSRV or isAny
                mdnsResponder_add(answers, seen, r.srv)
                additionals.append([r.a, r.nsec])
            end if
            if q.type = c.typeTXT or isAny then mdnsResponder_add(answers, seen, r.txt)
        else if name = hostName
            if q.type = c.typeA or isAny
                mdnsResponder_add(answers, seen, r.a)
                additionals.push(r.nsec)
            else if q.type = c.typeAAAA or q.type = c.typeNSEC
                mdnsResponder_add(answers, seen, r.nsec)
            end if
        end if
    end for
    if answers.count() = 0 then return invalid

    extra = []
    for each record in additionals
        mdnsResponder_add(extra, seen, record)
    end for
    return mdns_buildResponse(answers, extra)
end function

' RFC 6762 7.1 known-answer suppression for our PTR record.
function mdnsResponder_knownAnswer(query as object, service as object) as boolean
    for each known in query.answers
        if known.type = mdns_constants().typePTR and LCase(known.name) = LCase(service.serviceType) and known.data <> invalid and LCase(known.data) = LCase(service.fullName) and known.ttl > service.ttl / 2
            return true
        end if
    end for
    return false
end function

sub mdnsResponder_add(list as object, seen as object, record as object)
    key = LCase(record.name) + "|" + record.type.toStr()
    if seen.doesExist(key) then return
    seen[key] = true
    list.push(record)
end sub
