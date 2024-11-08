function init()
    m.append({
        answers: []
        ip: ""
        port: ""
        service: ""
        device: ""
    })
end function

function initobject(clientData) as boolean
    m.answers.append(clientData.answers)
    m.answers.append(clientData.additionalanswers)
    for each ans in m.answers
        if ans.type = 1
            m.ip = ans.rdata.trim()
        else if ans.type = 12
            m.device = ans.rdata.trim()
            m.service = ans.name.trim()
        else if ans.type = 33
            m.port = ans.port
        end if
    end for
    return true
end function

function getserviceip() as object
    return  m.ip
end function

function getservicename() as object
    return m.service
end function

function getservicedevice() as object
    return m.device
end function
    
function getservicePort() as object
    return m.port
end function