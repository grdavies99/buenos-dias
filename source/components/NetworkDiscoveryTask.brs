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
    deviceName = Createobject("roDeviceInfo").GetFriendlyName()
    payload = CreateObject("roByteArray")
    header = CreateObject("roByteArray")
    ' master
    ' payload.fromHexString("0000000000010000000000001253747265616d696e6720537469636b20344b085f616972706c6179045f746370056c6f63616c0000218001")
' 0000000000010000000000014506978656c203220426f6e736f69722044656d6f115f626f6e736f697264656d6f2e5f746370056c6f63616c0000108001

    ' header.fromHexString("01005e0000fbb2a62aaeb3ca0800450000aeece34000ff11eb11c0a801a5e00000fb14e914e9009a46bc")
    payload.fromHexString("0000000000010000000000001253747265616d696e6720537469636b20344b085f616972706c6179045f746370056c6f63616c0000ff8001")
    ' payload.fromHexString("0000000000010001000000000c5f626f6e736f697264656d6f045f746370056c6f63616c0000ff0001c00c000c000100001194001714506978656c203220426f6e736f69722044656d6fc00c")
    ?udp.SetMulticastLoop(true)
    udp.setMulticastTTL(255)
    ?udp.JoinGroup(addr)
    ' udp.send(payload, 40, payload.count()-0)
    udp.send(payload, 0, payload.count())
    
    continue = udp.eSuccess()
    While continue
        event = wait(0, msgPort)
        If type(event)="roSocketEvent"
            If event.getSocketID()=udp.getID()
                If udp.isReadable()
                    message = udp.receiveStr(512) ' max 512 characters
                    print "Received message: '"; message; "'"
                End If
            End If
        Else If event=invalid
            print "Timeout"
            ' udp.send(payload,0, payload.count()) ' periodic send
        End If
    End While
    udp.close() ' would happen automatically as udp goes out of scope

end function

