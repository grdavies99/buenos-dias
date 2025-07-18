'** 
  '** Example: Edit a Label size and color with BrightScript
  '**

  function init()
    m.top.setFocus(true)
    m.bonjourTask = m.top.findNode("udptask")
    m.bonjourTask.control = "RUN"
    m.bonjourTask.observeField("deepLink", "deepLinkHandler")
    m.bonjourTask.observeField("remote", "remoteHandler")
    m.videocontent = createObject("RoSGNode", "ContentNode")
    m.videocontent.title = "Sintel"
    m.videocontent.streamformat = "mp4"
    m.videocontent.url = "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4"

    m.video = m.top.findNode("myvideo")
    m.video.content = m.videocontent
    m.video.setFocus(true)
    m.video.control = "play"
    m.myLabelgroup = m.top.findNode("textbadge")
    m.labeltext = m.top.findNode("text")
    initTimer("showbadge")
  end function

  function initTimer(functionName as string)
    m.badgeTimer = createObject("roSGNode", "Timer")
    m.badgeTimer.repeat = false
    m.badgeTimer.duration = 10
    m.badgeTimer.control = "start"
    m.badgeTimer.ObserveField("fire", functionName)
  end function

  function showbadge()
    ?"showing label"
    m.myLabelgroup.visible = true
    m.labeltext.text = "open your phone"
    initTimer("hidebadge")
  end function

  function hidebadge()
    m.myLabelgroup.visible = false
  end function

  function deepLinkHandler(event as dynamic)
    evt = event.getData()
    ? "deepLinkHandler: " + evt
    m.videocontent.url = evt
    m.video.content = m.videocontent
    m.video.control = "play"
  end function

  function remoteHandler(event as dynamic)
    evt = event.getData()
    ? "remoteHandler: " + evt
    ' if evt <> invalid and evt <> ""
    '     m.videocontent.url = evt
    '     m.video.content = m.videocontent
    '     m.video.control = "play"
    ' end if
  end function