var AWS = require("aws-sdk");
var pg = require('pg');

var queue = process.env.AWSQURL;
var sqs = new AWS.SQS({ region: 'us-east-1'});
var params = {
  QueueUrl : queue,
  WaitTimeSeconds : 10
}

var i = 0;
var conString = "postgres://postgres:@localhost:9999/postgres";

var client = null;
pg.connect(conString, function(err, myclient, done) {
  if(err) {
    return console.error('could not connect to postgres', err);
  }else{
    client = myclient;
    client.query("Create table if not exists emp (firstname varchar(10),lastname varchar(10), age int)",function(err){
      if(err){
        console.log(err);
        client.end();
      }else{
        console.log('connected');
        readMessage();
      }
    });
  }
});

function readMessage(){
  sqs.receiveMessage(params, function(err, data) {
    if (err) 
    console.log('connection error',err, err.stack); // an error occurred
    else{   
      //console.log(data);           // successful response
      if(data['Messages']){
        msg = JSON.parse(data['Messages'][0]['Body']);
        rh = data['Messages'][0]['ReceiptHandle'];
        client.query('INSERT INTO emp (firstname,lastname,age) VALUES ($1,$2,$3)', [msg['firstname'],msg['lastname'],msg['age']], function(err, result) {
          if(err){
            console.log(err);
          }else{
            deleteMessage(rh);
          }
        });
      }
    }
  readMessage();
  });
}

function deleteMessage(rh){
  sqs.deleteMessage( { QueueUrl : queue, ReceiptHandle: rh }, function(err,data){
    if(err){
      console.log(err);
      deleteMessage(rh);
    }
  });
}



