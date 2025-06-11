function init()
    m.top.help = {
        "name": "SSDPConductor",
        "description": "Manages SSDP and local service tasks for network discovery.",
        "methods": [
            {
                "name": "createReciever",
                "description": "Creates a new local service receiver with the given parameters.",
                "params": {
                    "name": "String value: local service name",
                    "port": "integer value: Port number for the local service.",
                    "target": "String value: Target service name for the service.",
                }
            }
        ],
        "properties": {
            "recievers": "Array of local service receiver tasks.",
            "BroadIO": "AssocArray interface for broadcasting and receiving network messages.",
            "customCommands": "Array of custom commands for network tasks."
        }
    }
end function

function createReciever(params)
    BroadcastTask = CreateObject("roSGNode", "NetworkBroadcastTask")
    BroadcastTask.functionName = "initReciever"
    BroadcastTask.initParams = params
    BroadcastTask.id = params.name + "_" + params.port.toStr()
    BroadcastTask.control = "RUN"
    recievers = m.top.recievers
    if recievers = invalid
        m.top.recievers = [BroadcastTask]
    else
        recievers.push(BroadcastTask)
        m.top.recievers = recievers
    end if
end function