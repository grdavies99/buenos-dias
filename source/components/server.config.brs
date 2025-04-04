function serverConfig()
    return {
        ' server auth key
        "adgeAuthToken": "server12345",
        ' content server
        "contentServer":{
            "authToken": "content12345",
            "contentUrl": "http://localhost:8080",
        }
        ' array with possible server actions
        "serverActions": [
            "remote",
            "adContent",
            "serviceAuth",
            "deeplink",
            "content"
        ]   
    }
end function