sub init()
    m.top.functionName = "mdnsBrowser_run"
end sub

sub mdnsBrowser_run()
    c = mdns_constants()
    if m.top.serviceType = ""
        m.top.error = "serviceType is required"
        return
    end if

    port = CreateObject("roMessagePort")
    socket = mdns_openSocket(port)
    if socket = invalid
        m.top.error = "could not bind mDNS port 5353"
        return
    end if
    m.top.observeField("control", port)

    buffer = CreateObject("roByteArray")
    buffer[c.bufferSize - 1] = 0

    state = {
        serviceType: mdns_fqdn(m.top.serviceType)
        instances: {} ' lcase fullName -> { name, fullName, hostName, port, txt }
        hosts: {}     ' lcase hostName -> { ipAddress, ipv6Address }
        asked: {}     ' follow-up questions already sent
    }
    m.top.services = []

    clock = CreateObject("roTimespan")
    deadline = m.top.timeout * 1000
    ' RFC 6762 5.2: repeat the query with doubling intervals
    queryInterval = 1000
    nextQueryAt = 0

    while true
        now = clock.TotalMilliseconds()
        if deadline > 0 and now >= deadline then exit while
        if now >= nextQueryAt
            mdnsBrowser_send(socket, [{ name: state.serviceType, type: c.typePTR }])
            nextQueryAt = now + queryInterval
            if queryInterval < 60000 then queryInterval = queryInterval * 2
        end if

        timeout = nextQueryAt - now
        if deadline > 0 and deadline - now < timeout then timeout = deadline - now
        if timeout < 1 then timeout = 1
        event = wait(timeout, port)

        if type(event) = "roSGNodeEvent"
            if event.getField() = "control" and LCase(event.getData()) = "stop" then exit while
        else if type(event) = "roSocketEvent"
            if socket.isReadable()
                received = socket.receive(buffer, 0, c.bufferSize)
                if received > 0
                    try
                        msg = mdns_parseMessage(buffer, received)
                        if msg <> invalid and msg.isResponse and mdnsBrowser_absorb(state, msg)
                            m.top.services = mdnsBrowser_snapshot(state)
                            mdnsBrowser_resolve(socket, state)
                        end if
                    catch e
                        print "MdnsBrowser: ignoring unparseable packet: "; e.message
                    end try
                end if
            end if
            if not socket.eOK() then exit while
        end if
    end while

    socket.close()
end sub

sub mdnsBrowser_send(socket as object, questions as object)
    packet = mdns_buildQuery(questions)
    socket.send(packet, 0, packet.count())
end sub

' Merges a response into state. Returns true if anything we track changed.
function mdnsBrowser_absorb(state as object, msg as object) as boolean
    c = mdns_constants()
    suffix = "." + LCase(state.serviceType)
    changed = false
    records = []
    records.append(msg.answers)
    records.append(msg.additionals)

    for each record in records
        name = LCase(record.name)
        if record.data = invalid
            ' unsupported or malformed rdata
        else if record.type = c.typePTR and name = LCase(state.serviceType)
            key = LCase(record.data)
            if record.ttl = 0
                if state.instances.doesExist(key)
                    state.instances.delete(key)
                    changed = true
                end if
            else
                mdnsBrowser_instance(state, record.data)
                changed = true
            end if
        else if record.type = c.typeSRV and name.right(len(suffix)) = suffix
            instance = mdnsBrowser_instance(state, record.name)
            instance.hostName = record.data.target
            instance.port = record.data.port
            changed = true
        else if record.type = c.typeTXT and name.right(len(suffix)) = suffix
            mdnsBrowser_instance(state, record.name).txt = record.data
            changed = true
        end if
    end for

    ' second pass so addresses are matched against hosts named by SRV records in this same packet;
    ' only hosts we care about are kept, the group carries every device's records
    wanted = {}
    for each key in state.instances
        wanted[LCase(state.instances[key].hostName)] = true
    end for
    for each record in records
        name = LCase(record.name)
        if record.data <> invalid and (record.type = c.typeA or record.type = c.typeAAAA) and wanted.doesExist(name)
            if not state.hosts.doesExist(name) then state.hosts[name] = { ipAddress: "", ipv6Address: "" }
            if record.type = c.typeA
                state.hosts[name].ipAddress = record.data
            else
                state.hosts[name].ipv6Address = record.data
            end if
            changed = true
        end if
    end for
    return changed
end function

function mdnsBrowser_instance(state as object, fullName as string) as object
    key = LCase(fullName)
    if not state.instances.doesExist(key)
        name = fullName
        suffix = "." + LCase(state.serviceType)
        if key.right(len(suffix)) = suffix then name = fullName.left(len(fullName) - len(suffix))
        state.instances[key] = {
            name: name
            fullName: fullName
            hostName: ""
            port: 0
            txt: {}
        }
    end if
    return state.instances[key]
end function

' Asks once for any SRV/TXT/A records still missing.
sub mdnsBrowser_resolve(socket as object, state as object)
    c = mdns_constants()
    questions = []
    for each key in state.instances
        instance = state.instances[key]
        if instance.port = 0
            mdnsBrowser_ask(state, questions, instance.fullName, c.typeSRV)
            mdnsBrowser_ask(state, questions, instance.fullName, c.typeTXT)
        else if instance.hostName <> "" and not state.hosts.doesExist(LCase(instance.hostName))
            mdnsBrowser_ask(state, questions, instance.hostName, c.typeA)
        end if
    end for
    if questions.count() > 0 then mdnsBrowser_send(socket, questions)
end sub

sub mdnsBrowser_ask(state as object, questions as object, name as string, recordType as integer)
    key = LCase(name) + "|" + recordType.toStr()
    if state.asked.doesExist(key) then return
    state.asked[key] = true
    questions.push({ name: name, type: recordType })
end sub

function mdnsBrowser_snapshot(state as object) as object
    list = []
    for each key in state.instances
        instance = state.instances[key]
        host = state.hosts[LCase(instance.hostName)]
        entry = {
            name: instance.name
            fullName: instance.fullName
            serviceType: state.serviceType
            hostName: instance.hostName
            port: instance.port
            txt: instance.txt
            ipAddress: ""
            ipv6Address: ""
        }
        if host <> invalid
            entry.ipAddress = host.ipAddress
            entry.ipv6Address = host.ipv6Address
        end if
        entry.resolved = entry.port > 0 and entry.ipAddress <> ""
        list.push(entry)
    end for
    return list
end function
