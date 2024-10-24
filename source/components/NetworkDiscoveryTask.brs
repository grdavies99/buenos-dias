function init()
    'ip address 224.0.0.251  udp port  5353
    m.top.functionName = "getContent"
    
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
    udp.SetTTL(255)
    stop
    deviceName = Createobject("roDeviceInfo").GetFriendlyName()
    payload = CreateObject("roByteArray")
    ' 01005e0000fbbcd7d46cf913080045000054cb614000ff110cedc0a801a6e00000fb14e914e90040c77f000000000001000000000000
    payload.fromHexString("1253747265616d696e6720537469636b20344b085f676c616e7365045f746370056c6f63616c0000218001")
    ?payload.ToAsciiString()
    udp.send(payload, 0, payload.count())
    continue = udp.eOK()
    While continue
        event = wait(0, msgPort)
        If type(event)="roSocketEvent"
        If event.getSocketID()=udp.getID()
                If udp.isReadable()
                    message = udp.receiveStr(512) ' max 512 characters
                    ' print "Received message: '"; message; "'"
                End If
            End If
        Else If event=invalid
            print "Timeout"
            udp.sendStr(message) ' periodic send
        End If
    End While
    udp.close() ' would happen automatically as udp goes out of scope

end function