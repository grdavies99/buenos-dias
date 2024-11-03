function init()
    'ip address 224.0.0.251  udp port  5353
    m.top.functionName = "getContent"
    
end function

function getContent ()
    
    payload = CreateObject("roByteArray")
    header = {
        "query": "0000000000010000000000001",
        "response": "000084000001000000000000"
    }
    service = {
        "glanse": "5f676c616e73652e5f75647056c6f63616c",
        "airplay": "85f616972706c6179045f746370056c6f63616c00"
    }
    tail = {
        "question" : {
            "any": "00ff8001",
            "SRV": "00218001",
            "A": "00018001",
            "AAAA": "001c8001",
            "PTR": "000c8001"
        }
    }

    msgPort = createobject("roMessagePort")
    udp = createobject("roDatagramSocket")
    udp.setMessagePort(msgPort) 'notifications for udp come to msgPort
    addr = createobject("roSocketAddress")
    addr.setPort(5353)
    udp.setAddress(addr) ' bind to all host addresses on port 54321
    addr.SetHostName("224.0.0.251")
    udp.setSendToAddress(addr) ' peer IP and port
    udp.notifyReadable(true)

    accumulated = header.query + service.glanse + tail.question.any
    payload.fromHexString("000000000001000000000000085f616972706c6179045f746370056c6f63616c00000c0001")
    ?udp.SetMulticastLoop(true)
    udp.setMulticastTTL(255)
    ?udp.JoinGroup(addr)
    recieve = CreateObject("roByteArray")
    for i = 0 to 1024 
        recieve.Push(i) 
    end for
    udp.send(payload, 0, payload.count())
    continue = udp.eOk()
    While continue
        event = wait(0, msgPort)
        If type(event)="roSocketEvent"
            If event.getSocketID()=udp.getID() and udp.isReadable()
                    message = udp.receive(recieve, 0, 1024) ' max 512 characters
                    message = SafeTextConvert(recieve)
                    stop
            End If
        Else If event=invalid
            print "Timeout"
            ' udp.send(payload,0, payload.count()) ' periodic send
        End If
        continue = udp.eOk()
    End While
    stop
    udp.close() ' would happen automatically as udp goes out of scope

end function

function SafeTextConvert(bytearray)
    retValue = ""
    for each byte in bytearray
        if byte > 32
            retValue = retvalue+chr(byte)
        end if
    end for 
    return retValue
end function
