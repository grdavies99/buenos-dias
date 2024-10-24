var rokuDeploy = require('roku-deploy');

//deploy a .zip package of your project to a roku device
rokuDeploy.deploy({
    host: '192.168.1.152',
    password: 'abcd'
    //other options if necessary
}).then(function(){
    //it worked
}, function(error) {
    //it failed
    console.error(error);
});