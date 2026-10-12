function init() as void
    m.top.functionName = "awaitRequest"
    m.config = serverConfig()
    m.content = newContentList()
end function

function awaitRequest()
    messagePort = CreateObject("roMessagePort")
    connections = {}
    buffer = CreateObject("roByteArray")
    buffer[8192] = 0
    udp = CreateObject("roDatagramsocket")
    udp.setMessagePort(messagePort)

    addr = createobject("roSocketAddress")
    addr.setPort(16809)
    udp.setAddress(addr) ' bind to all host addresses on port 54321
    udp.notifyReadable(true)
    udp.setMulticastTTL(255)

    if not udp.eOK()
        print "Error creating listen socket"
    else
        print "server listening"
    end if

    buffer = CreateObject("roByteArray")
    buffer[8192] = 0
    closed = false
    while udp.eOK()
        event = wait(0, messagePort)
        If type(event)="roSocketEvent"
            ' If event.getSocketID()=udp.getID() and udp.isReadable()
                received = udp.receive(buffer, 0, 8192)
                address = udp.GetReceivedFromAddress()
                udp.setSendToAddress(address) ' set the address to send to

                print "Received from: "; address; " - "; received
                if received > 0
                    answer = buffer.ToAsciiString()
                    print "Received: '"; answer; "'"
                    validAction = false
                    m.actionData = []
                    actionData = answer.split(";")
                    if actionData.count() = 0
                        m.actionData = answer.split(":")
                    else
                        for each item in actionData
                            splitItem = item.split(":")
                            for each data in m.config.serverActions
                                if splitItem[0] = data
                                    m.actionData = splitItem
                                    handleValidAction(item, udp)
                                end if
                            end for
                        end for
                        buffer = CreateObject("roByteArray")
                        buffer[8192] = 0 
                        validAction = invalid
                    end if
                    
                    if validAction <> invalid and validAction
                        handleValidAction(answer, udp)
                        buffer = CreateObject("roByteArray")
                        buffer[8192] = 0
                    else if validAction <> invalid
                        print "Invalid action"
                        buffer = CreateObject("roByteArray")
                        buffer[8192] = 0
                    end if
                else if received=0 ' client closed
                    print "client closed connection"
                    closed = True
                end if
            end if
            if closed or not udp.eOK()
                udp.close()
            end if  
        ' end if
    end while

    print "Main loop exited"
    udp.close()
    for each id in connections
        connections[id].close()
    end for
End Function

Function handleValidAction(answer as String, connection as Object)
    if m.actionData[0] = m.config.serverActions[0]
        ' remote
        print "Echo input: '"; answer; "'"
        m.top.remote = m.actionData[1]
    else if m.actionData[0] = m.config.serverActions[1]
        ' ad content
        buffer = FormatJson(m.top.adContent)
        print "Echo input: '"; buffer; "'"
        connection.SendStr(buffer)
    else if m.actionData[0] = m.config.serverActions[2]
        ' service auth
        buffer = FormatJson(m.top.serviceAuth)
        print "Echo input: '"; buffer; "'"
        connection.SendStr(buffer)
        buffer = CreateObject("roByteArray")
    else if m.actionData[0] = m.config.serverActions[3]
        ' deeplink
        m.top.deeplink = m.actionData[1]
    else if m.actionData[0] = m.config.serverActions[4]
        ' content
        buffer = FormatJson(m.content)
        print "Echo input: '"; buffer; "'"
        connection.SendStr(buffer)
    else
        ' custom command
        m.top.customCommand = m.actionData
    end if
end function