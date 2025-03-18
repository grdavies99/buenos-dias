function init() as void
    m.top.functionName = "awaitRequest"
end function

function awaitRequest()
    messagePort = CreateObject("roMessagePort")
    connections = {}
    buffer = CreateObject("roByteArray")
    buffer[512] = 0
    tcpListen = CreateObject("roStreamSocket")
    tcpListen.setMessagePort(messagePort)
    addr = CreateObject("roSocketAddress")
    addr.setPort(16809)
    tcpListen.setAddress(addr)
    tcpListen.notifyReadable(true)
    tcpListen.listen(4)
    if not tcpListen.eOK()
        print "Error creating listen socket"
    else
        print "server listening"
    end if
    while True
        event = wait(0, messagePort)
        if type(event) = "roSocketEvent"
            changedID = event.getSocketID()
            if changedID = tcpListen.getID() and tcpListen.isReadable()
                ' New
                newConnection = tcpListen.accept()
                if newConnection = Invalid
                    print "accept failed"
                else
                    print "accepted new connection " newConnection.getID()
                    newConnection.notifyReadable(true)
                    newConnection.setMessagePort(messagePort)
                    connections[Stri(newConnection.getID())] = newConnection
                end if
            else
                ' Activity on an open connection
                connection = connections[Stri(changedID)]
                closed = False
                if connection.isReadable()
                    received = connection.receive(buffer, 0, 512)
                    ' ?" Received "; received;
                    if received > 0
                        answer = buffer.ToAsciiString()
                        print "Received: '"; answer; "'"
                        buffer = FormatJson({
                            "id": "12345",
                            "name": "Sample Product",
                            "description": "This is a sample product description.",
                            "price": 43.99,
                            "currency": "USD",
                            "image": "https://t3.ftcdn.net/jpg/02/36/99/22/360_F_236992283_sNOxCVQeFLd5pdqaKGh8DRGMZy7P4XKm.jpg",
                            "inStock": true
                          })
                        print "Echo input: '"; buffer; "'"
                        ?connection.SendStr(buffer)
                        buffer = CreateObject("roByteArray")
                        buffer[512] = 0
                    else if received=0 ' client closed
                        print "client closed connection"
                        closed = True
                    end if
                end if
                if closed or not connection.eOK()
                    print "closing connection " changedID
                    connection.close()
                    connections.delete(Stri(changedID))
                end if
            end if
        end if
    end while

    print "Main loop exited"
    tcpListen.close()
    for each id in connections
        connections[id].close()
    end for
End Function