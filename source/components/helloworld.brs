'** 
  '** Example: Edit a Label size and color with BrightScript
  '**

  function init()
    m.top.setFocus(true)
    m.myLabelgroup = m.top.findNode("myLabel")
    m.bonjourTask = m.top.findNode("udptask")
    m.bonjourTask.control = "RUN"

    m.bonjourTask.observeField("localclients", "handleClientsChanged")

    '**
    '** The full list of editable attributes can be located at:
    '** http://sdkdocs.roku.com/display/sdkdoc/Label#Label-Fields
    '**
  end function

  function handleClientsChanged(evt as dynamic)
    for each client in evt.getData()
      
      dataobject = CreateObject("rosgNode", "ClientDataObject")
      dataobject.callfunc("initobject", client)
      label = CreateObject("rosgNode", "Label")
      label.text = dataobject.callfunc("getservicedevice") + ", service type: " + dataobject.callfunc("getservicename") + ", IP Address: " + dataobject.callfunc("getserviceip") + ", Port: " + dataobject.callfunc("getservicePort").toStr()
      label.font.size=27
      label.color="0x72D7EEFF"
      m.myLabelgroup.appendChild(Label)
    end for
  end function