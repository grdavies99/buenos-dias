function init()
    'ip address 224.0.0.251  udp port  5353
    m.top.functionName = "getContent"
    m.responselength = 2048
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
    for i = 0 to m.responselength 
        recieve.Push(i)
        mask.push(i)
    end for
    serviceName = "_adge._udp.local" ' must match the name advertised by NetworkBroadcastTask.brs
    payload = CreateMDNSQuery(serviceName, 1)
    udp.send(payload, 0, payload.count())
    m.results = []
    continue = udp.eOk()
    While continue
        event = wait(0, msgPort)
        If type(event)="roSocketEvent"
            If event.getSocketID()=udp.getID() and udp.isReadable()
                    message = udp.receive(recieve, 0, m.responselength) ' max 512 characters
                    parsed = ParseMDNSResponse(recieve)
                    if parsed.ancount > 0 
                        for each ans in parsed.answers
                            if ans.name = serviceName then stop'm.results.push(parsed)
                            m.top.localclients = m.results
                        end for
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

' Helper function to read domain names in mDNS format (using compression if needed)
function ReadNamePointer(byteArray as Object, offset as Integer) as String
    name = ""
    length = byteArray[offset]
    offset += 1
    name += SafeTextConvert(byteArray.slice(offset, offset + length))
    offset += length
    return name
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

function CreateMDNSQuery(domainName as String, recordType as integer) as Object
    byteArray = CreateObject("roByteArray")
    
    ' Header section (12 bytes for mDNS)
    byteArray.Push(0)    ' ID high byte (0 for mDNS)
    byteArray.Push(0)    ' ID low byte (0 for mDNS)
    byteArray.Push(0)    ' Flags (QR, Opcode, AA, TC, RD)
    byteArray.Push(0)    ' Flags (RA, Z, RCODE)
    byteArray.Push(0)    ' QDCOUNT high byte (1 query)
    byteArray.Push(1)    ' QDCOUNT low byte (1 query)
    byteArray.Push(0)    ' ANCOUNT high byte (0 answers in query)
    byteArray.Push(0)    ' ANCOUNT low byte (0 answers in query)
    byteArray.Push(0)    ' NSCOUNT high byte (0)
    byteArray.Push(0)    ' NSCOUNT low byte (0)
    byteArray.Push(0)    ' ARCOUNT high byte (0)
    byteArray.Push(0)    ' ARCOUNT low byte (0)

    ' Question section
    ' Split domain name into labels (e.g., "example.local" -> ["example", "local"])
    labels = domainName.Split(".")

    ' Add each label to the byte array with length prefix
    for each label in labels
        label = label.split("")
        byteArray.Push(label.count())  ' Length of the label
        for i = 0 to label.count() - 1
            byteArray.Push(asc(label[i]))  ' ASCII value of each character in the label
        end for
    end for

    byteArray.Push(0)  ' End of domain name (null byte)

    ' QTYPE and QCLASS for mDNS query (0x0001 for A record, 0x000C for PTR, 0x8001 for any)
    byteArray.Push(0)    ' QTYPE high byte (e.g., A record)
    byteArray.Push(recordType)    ' QTYPE low byte
    byteArray.Push(0)    ' QCLASS high byte
    byteArray.Push(1)    ' QCLASS low byte (IN, Internet class)

    return byteArray
end function

