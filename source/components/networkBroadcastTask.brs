function init()
    'ip address 224.0.0.251  udp port  5353
    m.top.functionName = "getContent"
    m.responselength = 2048
    m.mdnsServer = CreateObject("roSGNode", "tcpServer")
    m.top.observeField("adContent", "handleAdContentChanged")
    m.top.observeField("serviceAuth", "handleServiceAuthChanged")
    m.mdnsServer.observeField("deepLink", "handleDeepLinkChanged")
    m.mdnsServer.control = "RUN"
end function

function getContent ()
    msgPort = createobject("roMessagePort")
    udp = createobject("roDatagramSocket")
    udp.setMessagePort(msgPort) 'notifications for udp come to msgPort
    addr = createobject("roSocketAddress")
    addr.setPort(5353)
    udp.setAddress(addr) ' bind to all host addresses on port 54321
    addr.SetHostName("224.0.0.251")
    udp.setSendToAddress(addr) ' peer IP and port
    udp.notifyReadable(true)
    udp.setMulticastTTL(255)
    recieve = CreateObject("roByteArray")
    mask = CreateObject("roByteArray")
    nsec = CreateObject("roByteArray")
    for i = 0 to m.responselength 
        recieve.Push(i)
        mask.push(i)
    end for
    di = createobject("roDeviceInfo")
    adgeName = "_adge._tcp.local"
    serviceName = "_services._dns-sd._udp.local"

    srv = {
        srvRecordName:di.GetFriendlyName()+"."+adgeName 
        Priority:0 
        weight: 0 
        port: 16809
        target: "gdevice.local"
    }    ' Add the NSEC record

    ip = di.GetIPAddrs()?.eth1
    ' di.GetConnectionInfo().ipv6
    payload = CreateMDNSAnswer(di.GetFriendlyName()+"."+adgeName, 4500, ip, adgeName, di.GetFriendlyName()+"."+adgeName, srv)
    udp.send(payload, 0, payload.count())
    m.results = []
    continue = udp.eOk()
    While continue
        event = wait(0, msgPort)
        If type(event)="roSocketEvent"
            If event.getSocketID()=udp.getID() and udp.isReadable()
                    message = udp.receive(recieve, 0, m.responselength) ' max 512 characters
                    parsed = ParseMDNSResponse(recieve)
                    if parsed.qdcount >= 1 
                        payl = []
                        if (parsed.questions[0].name = adgeName or parsed.questions[0].name = di.GetFriendlyName()+"."+adgeName or parsed.questions[0].name = srv.target)
                            AACount = 0
                            for each question in parsed.questions
                                ' ?question.name
                                if question.type = 12
                                    payl.push({ ttl: 4500, srvName: adgeName, ansType: 12, srv: srv.srvRecordName})
                                else if question.type = 1
                                    payl.push({ ttl: 4500, srvName: srv.target, ansType: 1, srv: ip})
                                else if question.type = 33
                                    payl.push({ ttl: 4500, srvName: srv.srvRecordName, ansType: 33,  srv: srv})
                                else if question.type = 16
                                    payl.push( { ttl: 4500, srvName: di.GetFriendlyName()+"."+adgeName, ansType: 16,  srv: srv})
                                else if question.type = 47
                                    payl.push({ ttl: 4500, srvName: srv.target, ansType: 47,  srv: {nextDomain: srv.target, typeBitMaps: [64]}})
                                end if
                            end for
                            ans = CreateAnswer(payl, AACount)
                            ' ?"sent payload"
                            udp.send(ans, 0, ans.count())
                        end if
                    end if
            End If
            continue = udp.eOk()
        Else If event=invalid
            print "Timeout"
            continue = false
        End If
        recieve = mask
    End While
    m.top.localclients = m.results
    udp.close() ' would happen automatically as udp goes out of scope

end function

function ParseMDNSResponse(byteArray as Object) as Object
    response = {
        id: 0
        qr: 0
        opcode: 0
        aa: 0
        tc: 0
        rd: 0
        ra: 0
        z: 0
        rcode: 0
        qdcount: 0
        ancount: 0
        nscount: 0
        arcount: 0
        questions: []
        answers: []
        additionalanswers: []
    }

    ' Parse the header (first 12 bytes)
    response.id = ReadUInt16(bytearray, 0)
    response.qr = (byteArray[2] >> 7) and 1
    response.opcode = (byteArray[2] >> 3) and 15
    response.aa = (byteArray[2] >> 2) and 1
    response.tc = (byteArray[2] >> 1) and 1
    response.rd = byteArray[2] and 1
    response.ra = (byteArray[3] >> 7) and 1
    response.z = (byteArray[3] >> 4) and 7
    response.rcode = byteArray[3] and 15

    response.qdcount = ReadUInt16(bytearray, 4)
    response.ancount = ReadUInt16(bytearray, 6)
    response.nscount = ReadUInt16(bytearray, 8)
    response.arcount = ReadUInt16(bytearray, 10)

    ' Parse questions section (just an example, you may need to adjust based on your needs)
    offset = 12
    for i = 0 to response.qdcount - 1
        if byteArray.count() <= offset then exit for
        question = {}
        question["name"] = ReadName(byteArray, offset)
        if len(question.name) > 1000 then return response
        ' ?question.name
        offset += len(question["name"]) + 2  ' Advance past name and null byte

        question["type"] = ReadUInt16(bytearray, offset)
        offset += 2
        question["class"] = ReadUInt16(bytearray, offset)
        offset += 2

        response.questions.Push(question)
    end for
    offset = 12
    ' Parse answers section (example for parsing the response records)
    for i = 0 to response.ancount - 1
        if byteArray.count() < offset + 12 then exit for
        answer = {}
        answer["name"] = ReadName(byteArray, offset)
        if len(answer.name) > 100 then return response
        ' ?answer.name
        offset += len(answer["name"]) + 2  ' Advance past name and null byte
        answer["type"] = ReadUInt16(bytearray, offset)
        offset += 2
        answer["class"] = ReadUInt16(bytearray, offset)
        offset += 2
        answer["ttl"] = (byteArray[offset] << 24) + (byteArray[offset + 1] << 16) + (byteArray[offset + 2] << 8) + byteArray[offset + 3]
        offset += 4
        answer["rdlength"] = ReadUInt16(bytearray, offset)
        offset += 2
        answer["rdata"] = SafeTextConvert(byteArray.slice(offset, offset + answer["rdlength"]))
        offset += answer["rdlength"]
        response.answers.Push(answer)
    end for
    if response.arcount > 0
        response.additionalanswers = parseAdditionalRecords(byteArray, offset, response.arcount)
    end if
    return response
end function

' Helper function to read domain names in mDNS format (using compression if needed)
function ReadName(byteArray as Object, offset as Integer) as String
    name = ""
    while byteArray[offset+1] <> invalid and byteArray[offset] > 0
        length = byteArray[offset]
        offset += 1
        name += SafeTextConvert(byteArray.slice(offset, offset + length))
        offset += length
        if byteArray[offset] <> invalid and byteArray[offset] > 0
            name += "."
        end if
    end while
    return name
end function

function parseAdditionalRecords(byteArray as object, offset as integer, arcount)
    ret = []
    i = 0
    while i< arcount
        namepointer = (ReadUInt16(byteArray, offset) >> 14) = 3        
        if namepointer
            answer = {}
            pointer = (ReadUInt16(byteArray, offset) and 16383)
            answer["name"] = ReadNamePointer(byteArray, pointer)
            offset += 2
            answer["type"] = ReadUInt16(bytearray, offset)
            offset += 4
            answer["ttl"] = (byteArray[offset] << 24) + (byteArray[offset + 1] << 16) + (byteArray[offset + 2] << 8) + byteArray[offset + 3]
            offset += 4
            answer["rdlength"] = ReadUInt16(bytearray, offset)
            offset += 2
            if answer["type"] = 1
                answer["rdata"] = ipv4Convert(byteArray.slice(offset, offset + answer["rdlength"]))
            else if answer["type"] = 28
                answer["rdata"] = ipv6Convert(byteArray.slice(offset, offset + answer["rdlength"]))
            else if answer["type"] = 33
                offsetcopy = offset
                answer["priority"] = ReadUInt16(bytearray, offsetcopy)
                offsetcopy +=2
                answer["weight"] = ReadUInt16(bytearray, offsetcopy)
                offsetcopy +=2
                answer["port"] = ReadUInt16(bytearray, offsetcopy)
                offsetcopy +=2
                answer["rdata"] = SafeTextConvert(byteArray.slice(offsetcopy, offset+ answer["rdlength"]))
                ' ?answer
            else
                answer["rdata"] = SafeTextConvert(byteArray.slice(offset, offset + answer["rdlength"]))
            end if
            offset += answer["rdlength"]
            ret.push(answer)
        end if
        i+=1
    end while
    return ret
end function


' Helper function to read domain names in mDNS format (using compression if needed)
function ReadNamePointer(byteArray as Object, offset as Integer) as String
    name = ""
    length = byteArray[offset]
    offset += 1
    name += SafeTextConvert(byteArray.slice(offset, offset + length))
    offset += length
    return name
end function

function SafeTextConvert(bytearray)
    retValue = ""
    for each byte in bytearray
        if byte > 32 and byte < 126
            retValue = retvalue+chr(byte)
        else
            retValue = retvalue+" "
        end if
    end for 
    return retValue
end function

function ipv4Convert(byteArray)
    ip = ""
    for each value in byteArray
        ip = ip+value.toStr()+"."
    end for
    return ip
end function

function ipv6Convert(byteArray)
    ip = ""
    for i = 0 to byteArray.count()-1 step 2
        ip = ip+byteArray.slice(i, i+1).toHexString()+":"
    end for
    return ip
end function

' Function to read a 16-bit integer from the byte array at a specific offset
function ReadUInt16(bytearray, offset)
    if offset+1<bytearray.count() then return (byteArray[offset] << 8) + byteArray[offset + 1]
    return 0
end function

function CreateMDNSAnswer(domainName as String, ttl as Integer, aRecordData as String, ptrRecordName as String, dnsSdName as String, srv as object) as Object
    byteArray = CreateObject("roByteArray")
    
    ' Header section (12 bytes for mDNS)
    byteArray.Push(0)    ' ID high byte (0 for mDNS)
    byteArray.Push(0)    ' ID low byte (0 for mDNS)
    byteArray.Push(132)  ' Flags: QR=1 (response), Opcode=0, AA=1 (authoritative answer)
    byteArray.Push(0)    ' Flags (continued)
    byteArray.Push(0)    ' QDCOUNT high byte (no queries in response)
    byteArray.Push(0)    ' QDCOUNT low byte
    byteArray.Push(0)    ' ANCOUNT high byte (4 answers)
    byteArray.Push(5)    ' ANCOUNT low byte (4 answers total)
    byteArray.Push(0)    ' NSCOUNT high byte (0)
    byteArray.Push(0)    ' NSCOUNT low byte (0)
    byteArray.Push(0)    ' ARCOUNT high byte (0)
    byteArray.Push(0)    ' ARCOUNT low byte (0)


    ' Add the PTR record _adge._tcp.local
    byteArray.Append(AddRecord(ptrRecordName, 12, ttl, srv.srvRecordName)) ' PTR record

    ' Add the DNS-SD PTR record
    byteArray.Append(AddRecord("_services._dns-sd._udp.local", 12, ttl, ptrRecordName)) ' DNS-SD PTR record

    ' Add the SRV record Roku Ultra._adge._tcp.local
    byteArray.Append(AddRecord(srv.srvRecordName, 33, ttl, {priority: srv.Priority, weight: srv.weight, port: srv.port, target: srv.target})) ' SRV record
    
    ' Add the NSEC record Roku Ultra.local
    byteArray.Append(AddRecord(srv.target, 47, ttl, {nextDomain: srv.target, typeBitMaps: [64]})) ' NSEC record

    ' Add the A record Roku Ultra.local
    byteArray.Append(AddRecord(srv.target, 1, ttl, aRecordData)) ' A record, IPv4 address
    return byteArray
end function

function CreateNSECAnswer(ttl as Integer, srv as object) as Object
    byteArray = CreateObject("roByteArray")
    
    ' Header section (12 bytes for mDNS)
    byteArray.Push(0)    ' ID high byte (0 for mDNS)
    byteArray.Push(0)    ' ID low byte (0 for mDNS)
    byteArray.Push(132)  ' Flags: QR=1 (response), Opcode=0, AA=1 (authoritative answer)
    byteArray.Push(0)    ' Flags (continued)
    byteArray.Push(0)    ' QDCOUNT high byte (no queries in response)
    byteArray.Push(0)    ' QDCOUNT low byte
    byteArray.Push(0)    ' ANCOUNT high byte (4 answers)
    byteArray.Push(1)    ' ANCOUNT low byte (4 answers total)
    byteArray.Push(0)    ' NSCOUNT high byte (0)
    byteArray.Push(0)    ' NSCOUNT low byte (0)
    byteArray.Push(0)    ' ARCOUNT high byte (0)
    byteArray.Push(0)    ' ARCOUNT low byte (0)

    ' Add the NSEC record Roku Ultra.local
    byteArray.Append(AddRecord(srv.target, 47, ttl, {nextDomain: srv.target, typeBitMaps: [64]})) ' NSEC record
    return byteArray
end function

function CreateAnswer(data, AACount) as Object
    byteArray = CreateObject("roByteArray")
    
    ' Header section (12 bytes for mDNS)
    byteArray.Push(0)    ' ID high byte (0 for mDNS)
    byteArray.Push(0)    ' ID low byte (0 for mDNS)
    byteArray.Push(132)  ' Flags: QR=1 (response), Opcode=0, AA=1 (authoritative answer)
    byteArray.Push(0)    ' Flags (continued)
    byteArray.Push(0)    ' QDCOUNT high byte (no queries in response)
    byteArray.Push(0)    ' QDCOUNT low byte
    byteArray.Push(0)    ' ANCOUNT high byte (4 answers)
    byteArray.Push(data.count()-AACount)    ' ANCOUNT low byte (4 answers total)
    byteArray.Push(0)    ' NSCOUNT high byte (0)
    byteArray.Push(0)    ' NSCOUNT low byte (0)
    byteArray.Push(0)    ' ARCOUNT high byte (0)
    byteArray.Push(AACount)    ' ARCOUNT low byte (0)
    ' Add the SRV record
    for each obj in data
        ' ?obj.srvName
        ' ?obj.ansType
        byteArray.Append(AddRecord(obj.srvName, obj.ansType, obj.ttl, obj.srv)) ' SRV record
    end for
    return byteArray
end function

function AddRecord(name as String, recordType as Integer, ttl as Integer, data as Object) as Object
    tempArray = CreateObject("roByteArray")
    
    ' Add Name
    labels = name.Split(".")
    for each label in labels
        tempArray.Push(label.len())
        label = label.split("")
        for i = 0 to label.count() - 1
            tempArray.Push(asc(label[i]))
        end for
    end for
    tempArray.Push(0) ' End of domain name
    
    ' Add Type and Class
    tempArray.Push(0)             ' TYPE high byte
    tempArray.Push(recordType)    ' TYPE low byte
    tempArray.Push(0)             ' CLASS high byte
    tempArray.Push(1)             ' CLASS low byte (IN)
    
    ' Add TTL
    tempArray.Push((ttl >> 24) and 255) ' TTL byte 1
    tempArray.Push((ttl >> 16) and 255) ' TTL byte 2
    tempArray.Push((ttl >> 8) and 255)  ' TTL byte 3
    tempArray.Push(ttl and 255)         ' TTL byte 4
    
    ' Add RDATA
    if recordType = 1 then ' A record (IPv4 address)
        ipParts = data.Split(".")
        tempArray.Push(0)    ' RDLENGTH high byte
        tempArray.Push(4)    ' RDLENGTH low byte
        for each part in ipParts
            tempArray.Push(val(part))
        end for
    else if recordType = 12 then ' PTR record (domain name)
        resourceLabels = data.Split(".")
        resourceDataLength = 0
        rdataArray = CreateObject("roByteArray")
        for each label in resourceLabels
            rdataArray.Push(label.len())
            label = label.split("")
            for i = 0 to label.count() - 1
                rdataArray.Push(asc(label[i]))
            end for
            resourceDataLength += label.count() + 1
        end for
        rdataArray.Push(0) ' End of domain name
        resourceDataLength += 1
        tempArray.Push((resourceDataLength >> 8) and 255) ' RDLENGTH high byte
        tempArray.Push(resourceDataLength and 255)        ' RDLENGTH low byte
        tempArray.Append(rdataArray)
    else if recordType = 33 then ' SRV record
        rdataArray = CreateObject("roByteArray")
        rdataArray.Push((data.priority >> 8) and 255) ' Priority high byte
        rdataArray.Push(data.priority and 255)        ' Priority low byte
        rdataArray.Push((data.weight >> 8) and 255)   ' Weight high byte
        rdataArray.Push(data.weight and 255)          ' Weight low byte
        rdataArray.Push((data.port >> 8) and 255)     ' Port high byte
        rdataArray.Push(data.port and 255)            ' Port low byte

        ' Encode target domain
        targetLabels = data.target.Split(".")
        for each label in targetLabels
            rdataArray.Push(label.len())
            label = label.split("")
            for i = 0 to label.count() - 1
                rdataArray.Push(asc(label[i]))
            end for
        end for
        rdataArray.Push(0) ' End of domain name
        
        rdataLength = rdataArray.Count()
        tempArray.Push((rdataLength >> 8) and 255) ' RDLENGTH high byte
        tempArray.Push(rdataLength and 255)        ' RDLENGTH low byte
        tempArray.Append(rdataArray)
    else if recordtype = 16 then
        rdataArray = CreateObject("roByteArray")
        txtRecord = []
        for each key in data
            value = data[key]
            pair = key + "=" + value.toStr()
            txtRecord.push(pair + chr(0))  ' Null-terminate each key-value pair
        end for
        for each label in txtRecord
            rdataArray.Push(label.len())
            label = label.split("")
            for i = 0 to label.count() - 1
                rdataArray.Push(asc(label[i]))
            end for
        end for

        rdataArray.Push(0) ' End of domain name
        
        rdataLength = rdataArray.Count()
        tempArray.Push((rdataLength >> 8) and 255) ' RDLENGTH high byte
        tempArray.Push(rdataLength and 255)        ' RDLENGTH low byte
        tempArray.Append(rdataArray)

    else if recordType = 47 then ' NSEC record
        rdataArray = CreateObject("roByteArray")
        
        ' Next Domain Name
        nextDomainLabels = data.nextDomain.Split(".")
        for each label in nextDomainLabels
            rdataArray.Push(label.len())
            label = label.split("")
            for i = 0 to label.count() - 1
                rdataArray.Push(asc(label[i]))
            end for
        end for
        rdataArray.Push(0) ' End of domain name
        
        ' Type Bit Map
        for each block in data.typeBitMaps
                rdataArray.Push(block)
        end for
        rdataArray.Push(0) ' End of domain name
        rdataLength = rdataArray.Count()
        tempArray.Push((rdataLength >> 8) and 255) ' RDLENGTH high byte
        tempArray.Push(rdataLength and 255)        ' RDLENGTH low byte
        tempArray.Append(rdataArray)
    end if

    return tempArray
end function

function handleAdContentChanged(evt as dynamic)
    data = evt.getData()
    m.mdnsServer.adContent = data
end function

function handleServiceAuthChanged(evt as dynamic)
    data = evt.getData()
    m.mdnsServer.serviceAuth = data
end function

function handleDeepLinkChanged(evt as dynamic)
    data = evt.getData()
    ? "handleDeepLinkChanged: " + data
    m.top.deepLink = data
end function