console.log('Loading function');
var AWS = require('aws-sdk');

var sqs = new AWS.SQS({ region: 'us-east-1'});
var queue = "<queueURL>";



function randomString()
{
  var text = "";
  var possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

  for( var i=0; i < 5; i++ )
    text += possible.charAt(Math.floor(Math.random() * possible.length));

  return text;
}

function makeage(){

  return Math.floor(Math.random() * (120 - 1 ) + 1);
}



exports.handler = function(event, context) {
  //   console.log('Received event:', JSON.stringify(event, null, 2));
  var firstname = randomString();
  var lastname = randomString();
  var age = makeage();
  var msg = {"firstname" : firstname, "lastname" : lastname, "age" : age};
  var params = {
    MessageBody : JSON.stringify(msg) ,
    QueueUrl : queue
  };
  sqs.sendMessage(params, function(err,data){
    if(err){
      console.log(err);

    }else{
      context.succeed();
    }

  });
}
