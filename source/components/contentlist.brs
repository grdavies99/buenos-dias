' Builds the "content" catalog served to companion clients over the UDP
' command channel (see udpServer.brs's "content" action). Sourced from the
' bundled IPTV playlist (pkg:/eng.m3u) when present, falling back to the
' original Blender Foundation demo reel if it's missing.
'
' maxChannels is intentionally small: the whole catalog goes out as ONE
' udp.SendStr() call (roDatagramSocket, not TCP), which only reliably
' survives a single unfragmented UDP datagram (~1200 safe bytes). The
' bundled playlist has ~3000 channels - sending them all would silently
' fragment and likely get dropped on a real network, not just be "slow".
function newContentList() as object
    maxChannels = 10
    text = ReadAsciiFile("pkg:/eng.m3u")
    if text = "" then return defaultContentList()

    channels = ParseM3U(text, maxChannels)
    if channels.count() = 0 then return defaultContentList()
    return channels
end function

' Parses extended M3U (#EXTINF metadata line + URL line pairs) into the same
' shape the rest of the channel expects: description/sources/subtitle/thumb/title/id.
function ParseM3U(text as String, maxChannels as Integer) as Object
    channels = []
    lines = text.Replace(chr(13), "").Split(chr(10))

    havePending = false
    pendingLogo = ""
    pendingGroup = ""
    pendingTitle = ""

    for each rawLine in lines
        line = rawLine.Trim()
        if channels.count() >= maxChannels
            exit for
        else if Left(line, 8) = "#EXTINF:"
            pendingLogo = ExtractM3UAttr(line, "tvg-logo")
            pendingGroup = ExtractM3UAttr(line, "group-title")
            pendingTitle = ExtractM3UTitle(line)
            havePending = true
        else if line <> "" and Left(line, 1) <> "#" and havePending
            channels.push({
                "description": pendingGroup
                "sources": [line]
                "subtitle": pendingGroup
                "thumb": pendingLogo
                "title": pendingTitle
                "id": channels.count().toStr()
            })
            havePending = false
        end if
    end for

    return channels
end function

' Reads a quoted #EXTINF attribute, eg key="tvg-logo" -> ExtractM3UAttr(line, "tvg-logo").
function ExtractM3UAttr(line as String, key as String) as String
    marker = key + chr(61) + chr(34) ' ="
    startIdx = Instr(1, line, marker)
    if startIdx = 0 then return ""
    startPos = startIdx + Len(marker)
    endPos = Instr(startPos, line, chr(34))
    if endPos = 0 then return ""
    return Mid(line, startPos, endPos - startPos)
end function

' The channel's display name is everything after the LAST comma on the
' #EXTINF line (the standard extended-M3U convention).
function ExtractM3UTitle(line as String) as String
    lastComma = 0
    searchFrom = 1
    while true
        idx = Instr(searchFrom, line, ",")
        if idx = 0 then exit while
        lastComma = idx
        searchFrom = idx + 1
    end while
    if lastComma = 0 then return ""
    return Mid(line, lastComma + 1)
end function

function defaultContentList() as object
    return [
        { "description" : "Big Buck Bunny tells the story of a giant rabbit with a heart bigger than himself. When one sunny day three rodents rudely harass him, something snaps... and the rabbit ain't no bunny anymore! In the typical cartoon tradition he prepares the nasty rodents a comical revenge.\n\nLicensed under the Creative Commons Attribution license\nhttp://www.bigbuckbunny.org",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4" ],
          "subtitle" : "By Blender Foundation",
          "thumb" : "images/BigBuckBunny.jpg",
          "title" : "Big Buck Bunny",
          "id" : "1"
        },
        { "description" : "The first Blender Open Movie from 2006",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4" ],
          "subtitle" : "By Blender Foundation",
          "thumb" : "images/ElephantsDream.jpg",
          "title" : "Elephant Dream",
          "id" : "2"
        },
        { "description" : "HBO GO now works with Chromecast -- the easiest way to enjoy online video on your TV. For when you want to settle into your Iron Throne to watch the latest episodes. For $35.\nLearn how to use Chromecast with HBO GO and more at google.com/chromecast.",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4" ],
          "subtitle" : "By Google",
          "thumb" : "images/ForBiggerBlazes.jpg",
          "title" : "For Bigger Blazes",
          "id" : "3"
        },
        { "description" : "Introducing Chromecast. The easiest way to enjoy online video and music on your TV—for when Batman's escapes aren't quite big enough. For $35. Learn how to use Chromecast with Google Play Movies and more at google.com/chromecast.",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4" ],
          "subtitle" : "By Google",
          "thumb" : "images/ForBiggerEscapes.jpg",
          "title" : "For Bigger Escape",
          "id" : "4"
        },
        { "description" : "Introducing Chromecast. The easiest way to enjoy online video and music on your TV. For $35.  Find out more at google.com/chromecast.",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4" ],
          "subtitle" : "By Google",
          "thumb" : "images/ForBiggerFun.jpg",
          "title" : "For Bigger Fun",
          "id" : "5"
        },
        { "description" : "Introducing Chromecast. The easiest way to enjoy online video and music on your TV—for the times that call for bigger joyrides. For $35. Learn how to use Chromecast with YouTube and more at google.com/chromecast.",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4" ],
          "subtitle" : "By Google",
          "thumb" : "images/ForBiggerJoyrides.jpg",
          "title" : "For Bigger Joyrides",
          "id" : "6"
        },
        { "description" :"Introducing Chromecast. The easiest way to enjoy online video and music on your TV—for when you want to make Buster's big meltdowns even bigger. For $35. Learn how to use Chromecast with Netflix and more at google.com/chromecast.",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4" ],
          "subtitle" : "By Google",
          "thumb" : "images/ForBiggerMeltdowns.jpg",
          "title" : "For Bigger Meltdowns",
          "id" : "7"
        },
        { "description" : "Sintel is an independently produced short film, initiated by the Blender Foundation as a means to further improve and validate the free/open source 3D creation suite Blender. With initial funding provided by 1000s of donations via the internet community, it has again proven to be a viable development model for both open 3D technology as for independent animation film.\nThis 15 minute film has been realized in the studio of the Amsterdam Blender Institute, by an international team of artists and developers. In addition to that, several crucial technical and creative targets have been realized online, by developers and artists and teams all over the world.\nwww.sintel.org",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4" ],
          "subtitle" : "By Blender Foundation",
          "thumb" : "images/Sintel.jpg",
          "title" : "Sintel",
          "id" : "8"
        },
        { "description" : "Smoking Tire takes the all-new Subaru Outback to the highest point we can find in hopes our customer-appreciation Balloon Launch will get some free T-shirts into the hands of our viewers.",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4" ],
          "subtitle" : "By Garage419",
          "thumb" : "images/SubaruOutbackOnStreetAndDirt.jpg",
          "title" : "Subaru Outback On Street And Dirt",
          "id" : "9"
        },
        { "description" : "Tears of Steel was realized with crowd-funding by users of the open source 3D creation tool Blender. Target was to improve and test a complete open and free pipeline for visual effects in film - and to make a compelling sci-fi film in Amsterdam, the Netherlands.  The film itself, and all raw material used for making it, have been released under the Creatieve Commons 3.0 Attribution license. Visit the tearsofsteel.org website to find out more about this, or to purchase the 4-DVD box with a lot of extras.  (CC) Blender Foundation - http://www.tearsofsteel.org",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4" ],
          "subtitle" : "By Blender Foundation",
          "thumb" : "images/TearsOfSteel.jpg",
          "title" : "Tears of Steel",
          "id" : "10"
        },
        { "description" : "The Smoking Tire heads out to Adams Motorsports Park in Riverside, CA to test the most requested car of 2010, the Volkswagen GTI. Will it beat the Mazdaspeed3's standard-setting lap time? Watch and see...",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/VolkswagenGTIReview.mp4" ],
          "subtitle" : "By Garage419",
          "thumb" : "images/VolkswagenGTIReview.jpg",
          "title" : "Volkswagen GTI Review",
          "id" : "11"
        },
        { "description" : "The Smoking Tire is going on the 2010 Bullrun Live Rally in a 2011 Shelby GT500, and posting a video from the road every single day! The only place to watch them is by subscribing to The Smoking Tire or watching at BlackMagicShine.com",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4" ],
          "subtitle" : "By Garage419",
          "thumb" : "images/WeAreGoingOnBullrun.jpg",
          "title" : "We Are Going On Bullrun",
          "id" : "12"
        },
        { "description" : "The Smoking Tire meets up with Chris and Jorge from CarsForAGrand.com to see just how far $1,000 can go when looking for a car.The Smoking Tire meets up with Chris and Jorge from CarsForAGrand.com to see just how far $1,000 can go when looking for a car.",
          "sources" : [ "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WhatCarCanYouGetForAGrand.mp4" ],
          "subtitle" : "By Garage419",
          "thumb" : "images/WhatCarCanYouGetForAGrand.jpg",
          "title" : "What care can you get for a grand?",
          "id" : "13"
        }
    ]
end function
