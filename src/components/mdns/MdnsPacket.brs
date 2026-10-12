'*************************************************************
'** mDNS / DNS-SD wire format (RFC 1035, RFC 6762, RFC 6763)
'** Shared by MdnsResponder and MdnsBrowser.
'*************************************************************

function mdns_constants() as object
    return {
        address: "224.0.0.251"
        port: 5353
        typeA: 1
        typePTR: 12
        typeTXT: 16
        typeAAAA: 28
        typeSRV: 33
        typeNSEC: 47
        typeANY: 255
        classIN: 1
        cacheFlush: &h8000
        metaQueryName: "_services._dns-sd._udp.local"
        bufferSize: 9000
    }
end function

' Opens a UDP socket bound to 5353, joined to the mDNS group, sending to the group.
' Returns invalid if the port can't be bound.
function mdns_openSocket(port as object) as dynamic
    c = mdns_constants()
    socket = CreateObject("roDatagramSocket")
    socket.setMessagePort(port)
    ' the OS or another task (eg. a browser next to a responder) may already hold 5353
    socket.setReuseAddr(true)

    bindAddr = CreateObject("roSocketAddress")
    bindAddr.setPort(c.port)
    if not socket.setAddress(bindAddr) then return invalid

    group = CreateObject("roSocketAddress")
    group.setHostName(c.address)
    group.setPort(c.port)
    ' binding alone does not deliver multicast traffic - the group must be joined
    if not socket.joinGroup(group) then print "mdns: failed to join "; c.address; " - queries may not be received"
    socket.setMulticastTTL(255)
    socket.setSendToAddress(group)
    socket.notifyReadable(true)
    return socket
end function

' Normalises a name to a fully qualified .local name without a trailing dot.
function mdns_fqdn(name as string) as string
    name = name.trim()
    while name.right(1) = "."
        name = name.left(len(name) - 1)
    end while
    if name = "" then return ""
    if LCase(name.right(6)) <> ".local" and LCase(name) <> "local" then name = name + ".local"
    return name
end function

' First non-empty IPv4 address across interfaces (Roku reports eg. "wifi", "eth1").
function mdns_localIPv4() as dynamic
    addrs = CreateObject("roDeviceInfo").GetIPAddrs()
    if addrs = invalid then return invalid
    for each iface in addrs
        ip = addrs[iface]
        if ip <> invalid and ip <> "" and ip.instr(":") < 0 then return ip
    end for
    return invalid
end function

'-------------------------------------------------------------
' Encoding
'-------------------------------------------------------------

' questions: [{ name, type }]
function mdns_buildQuery(questions as object) as object
    bytes = CreateObject("roByteArray")
    mdns_writeHeader(bytes, 0, questions.count(), 0, 0)
    for each q in questions
        mdns_writeName(bytes, q.name)
        mdns_writeUInt16(bytes, q.type)
        mdns_writeUInt16(bytes, mdns_constants().classIN)
    end for
    return bytes
end function

' answers / additionals: [{ name, type, ttl, cacheFlush, data }] - see mdns_encodeRdata for data shapes
function mdns_buildResponse(answers as object, additionals as object) as object
    bytes = CreateObject("roByteArray")
    ' QR=1 (response), AA=1 (authoritative)
    mdns_writeHeader(bytes, &h8400, 0, answers.count(), additionals.count())
    for each record in answers
        mdns_writeRecord(bytes, record)
    end for
    for each record in additionals
        mdns_writeRecord(bytes, record)
    end for
    return bytes
end function

sub mdns_writeHeader(bytes as object, flags as integer, qdcount as integer, ancount as integer, arcount as integer)
    mdns_writeUInt16(bytes, 0) ' ID is always 0 for multicast
    mdns_writeUInt16(bytes, flags)
    mdns_writeUInt16(bytes, qdcount)
    mdns_writeUInt16(bytes, ancount)
    mdns_writeUInt16(bytes, 0) ' NSCOUNT
    mdns_writeUInt16(bytes, arcount)
end sub

sub mdns_writeRecord(bytes as object, record as object)
    c = mdns_constants()
    mdns_writeName(bytes, record.name)
    mdns_writeUInt16(bytes, record.type)
    recordClass = c.classIN
    if record.cacheFlush then recordClass = recordClass or c.cacheFlush
    mdns_writeUInt16(bytes, recordClass)
    mdns_writeUInt32(bytes, record.ttl)
    rdata = mdns_encodeRdata(record.type, record.data)
    mdns_writeUInt16(bytes, rdata.count())
    bytes.append(rdata)
end sub

' A: "a.b.c.d" | PTR: name | TXT: {key: value} | SRV: {priority, weight, port, target} | NSEC: {nextDomain, types: []}
function mdns_encodeRdata(recordType as integer, data as dynamic) as object
    c = mdns_constants()
    rdata = CreateObject("roByteArray")
    if recordType = c.typeA
        for each part in data.split(".")
            rdata.push(val(part) and 255)
        end for
    else if recordType = c.typePTR
        mdns_writeName(rdata, data)
    else if recordType = c.typeTXT
        mdns_writeTxt(rdata, data)
    else if recordType = c.typeSRV
        mdns_writeUInt16(rdata, data.priority)
        mdns_writeUInt16(rdata, data.weight)
        mdns_writeUInt16(rdata, data.port)
        mdns_writeName(rdata, data.target)
    else if recordType = c.typeNSEC
        mdns_writeName(rdata, data.nextDomain)
        mdns_writeTypeBitmap(rdata, data.types)
    end if
    return rdata
end function

sub mdns_writeName(bytes as object, name as string)
    for each label in name.split(".")
        if label <> ""
            mdns_writeCharacterString(bytes, label, 63)
        end if
    end for
    bytes.push(0)
end sub

' Length-prefixed UTF-8 string, truncated to maxLength bytes.
sub mdns_writeCharacterString(bytes as object, text as string, maxLength as integer)
    textBytes = CreateObject("roByteArray")
    textBytes.fromAsciiString(text)
    size = textBytes.count()
    if size > maxLength then size = maxLength
    bytes.push(size)
    for i = 0 to size - 1
        bytes.push(textBytes[i])
    end for
end sub

' Each entry is "key=value"; a boolean true value is written as a bare "key" (RFC 6763 6.4).
sub mdns_writeTxt(bytes as object, txt as dynamic)
    start = bytes.count()
    if txt <> invalid
        for each key in txt
            value = txt[key]
            valueType = type(value)
            if valueType = "Boolean" or valueType = "roBoolean"
                if value then mdns_writeCharacterString(bytes, key, 255)
            else if valueType = "String" or valueType = "roString"
                mdns_writeCharacterString(bytes, key + "=" + value, 255)
            else if value <> invalid
                mdns_writeCharacterString(bytes, key + "=" + value.toStr(), 255)
            end if
        end for
    end if
    ' an empty TXT record is a single zero-length string
    if bytes.count() = start then bytes.push(0)
end sub

' Single window (types < 256) NSEC type bitmap (RFC 4034 4.1.2).
sub mdns_writeTypeBitmap(bytes as object, types as object)
    maxType = 0
    for each t in types
        if t > maxType then maxType = t
    end for
    bitmap = CreateObject("roByteArray")
    for i = 0 to maxType \ 8
        bitmap.push(0)
    end for
    for each t in types
        bitmap[t \ 8] = bitmap[t \ 8] or (128 >> (t mod 8))
    end for
    bytes.push(0) ' window block
    bytes.push(bitmap.count())
    bytes.append(bitmap)
end sub

sub mdns_writeUInt16(bytes as object, value as integer)
    bytes.push((value >> 8) and 255)
    bytes.push(value and 255)
end sub

sub mdns_writeUInt32(bytes as object, value as integer)
    bytes.push((value >> 24) and 255)
    bytes.push((value >> 16) and 255)
    bytes.push((value >> 8) and 255)
    bytes.push(value and 255)
end sub

'-------------------------------------------------------------
' Decoding
'-------------------------------------------------------------

' Parses the first `length` bytes of a packet. Returns invalid if the header is
' unreadable; sections stop at the first malformed record.
' {
'   isResponse, questions: [{ name, type, unicastResponse }],
'   answers / authorities / additionals: [{ name, type, cacheFlush, ttl, data }]
' }
function mdns_parseMessage(bytes as object, length as integer) as dynamic
    if length < 12 then return invalid
    flags = mdns_readUInt16(bytes, 2)
    msg = {
        id: mdns_readUInt16(bytes, 0)
        isResponse: (flags and &h8000) <> 0
        questions: []
        answers: []
        authorities: []
        additionals: []
    }
    qdcount = mdns_readUInt16(bytes, 4)
    offset = 12

    for i = 1 to qdcount
        nm = mdns_readName(bytes, offset, length)
        if nm = invalid or nm.next + 4 > length then return msg
        questionClass = mdns_readUInt16(bytes, nm.next + 2)
        msg.questions.push({
            name: nm.name
            type: mdns_readUInt16(bytes, nm.next)
            unicastResponse: (questionClass and &h8000) <> 0
        })
        offset = nm.next + 4
    end for

    sections = [msg.answers, msg.authorities, msg.additionals]
    counts = [mdns_readUInt16(bytes, 6), mdns_readUInt16(bytes, 8), mdns_readUInt16(bytes, 10)]
    for s = 0 to 2
        for i = 1 to counts[s]
            parsed = mdns_readRecord(bytes, offset, length)
            if parsed = invalid then return msg
            sections[s].push(parsed.record)
            offset = parsed.next
        end for
    end for
    return msg
end function

function mdns_readRecord(bytes as object, offset as integer, length as integer) as dynamic
    c = mdns_constants()
    nm = mdns_readName(bytes, offset, length)
    if nm = invalid or nm.next + 10 > length then return invalid
    p = nm.next
    recordClass = mdns_readUInt16(bytes, p + 2)
    rdlength = mdns_readUInt16(bytes, p + 8)
    rdStart = p + 10
    rdEnd = rdStart + rdlength
    if rdEnd > length then return invalid

    record = {
        name: nm.name
        type: mdns_readUInt16(bytes, p)
        cacheFlush: (recordClass and c.cacheFlush) <> 0
        ttl: mdns_readUInt32(bytes, p + 4)
        data: invalid
    }

    if record.type = c.typeA and rdlength = 4
        record.data = bytes[rdStart].toStr() + "." + bytes[rdStart + 1].toStr() + "." + bytes[rdStart + 2].toStr() + "." + bytes[rdStart + 3].toStr()
    else if record.type = c.typeAAAA and rdlength = 16
        groups = []
        for g = 0 to 7
            groups.push(LCase(StrI(mdns_readUInt16(bytes, rdStart + g * 2), 16)))
        end for
        record.data = groups.join(":")
    else if record.type = c.typePTR
        target = mdns_readName(bytes, rdStart, length)
        if target <> invalid then record.data = target.name
    else if record.type = c.typeSRV and rdlength >= 7
        target = mdns_readName(bytes, rdStart + 6, length)
        if target <> invalid
            record.data = {
                priority: mdns_readUInt16(bytes, rdStart)
                weight: mdns_readUInt16(bytes, rdStart + 2)
                port: mdns_readUInt16(bytes, rdStart + 4)
                target: target.name
            }
        end if
    else if record.type = c.typeTXT
        record.data = mdns_readTxt(bytes, rdStart, rdEnd)
    end if

    return { record: record, next: rdEnd }
end function

' Reads a (possibly compressed) domain name. Returns { name, next } where next is
' the offset just past the name in the original position, or invalid if malformed.
function mdns_readName(bytes as object, offset as integer, length as integer) as dynamic
    labels = []
    cursor = offset
    nextOffset = -1
    jumps = 0
    terminated = false
    while cursor < length
        size = bytes[cursor]
        if size = 0
            cursor += 1
            terminated = true
            exit while
        else if (size and &hC0) = &hC0
            ' compression pointer
            if cursor + 1 >= length then return invalid
            if nextOffset < 0 then nextOffset = cursor + 2
            cursor = ((size and &h3F) << 8) or bytes[cursor + 1]
            jumps += 1
            if jumps > 32 then return invalid ' pointer loop
        else if (size and &hC0) <> 0
            return invalid ' reserved label types
        else
            if cursor + 1 + size > length then return invalid
            labels.push(mdns_readString(bytes, cursor + 1, size))
            cursor += 1 + size
        end if
    end while
    if not terminated then return invalid
    if nextOffset < 0 then nextOffset = cursor
    return { name: labels.join("."), next: nextOffset }
end function

' TXT rdata -> { key: value }; a bare "key" becomes key: true (RFC 6763 6.4).
function mdns_readTxt(bytes as object, start as integer, finish as integer) as object
    txt = {}
    cursor = start
    while cursor < finish
        size = bytes[cursor]
        if cursor + 1 + size > finish then exit while
        if size > 0
            entry = mdns_readString(bytes, cursor + 1, size)
            eq = entry.instr("=")
            if eq > 0
                txt[entry.left(eq)] = entry.mid(eq + 1)
            else if eq < 0
                txt[entry] = true
            end if
        end if
        cursor += 1 + size
    end while
    return txt
end function

function mdns_readString(bytes as object, start as integer, count as integer) as string
    chunk = CreateObject("roByteArray")
    for i = start to start + count - 1
        chunk.push(bytes[i])
    end for
    return chunk.toAsciiString()
end function

function mdns_readUInt16(bytes as object, offset as integer) as integer
    return (bytes[offset] << 8) or bytes[offset + 1]
end function

function mdns_readUInt32(bytes as object, offset as integer) as integer
    return (bytes[offset] << 24) or (bytes[offset + 1] << 16) or (bytes[offset + 2] << 8) or bytes[offset + 3]
end function
