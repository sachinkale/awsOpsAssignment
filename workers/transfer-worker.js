var AWS = require("aws-sdk");
var pg = require('pg');

var queue = process.env.AWSTQURL;
var sqs = new AWS.SQS({ region: 'us-east-1'});
var params = {
  QueueUrl : queue,
  WaitTimeSeconds : 10
}

var conString = "postgres://postgres:@localhost:9999/postgres";
AWS.config.update({
  region: 'us-east-1'
});

var docClient = new AWS.DynamoDB.DocumentClient();

function readMessage(){
  sqs.receiveMessage(params, function(err, data) {
    if (err) 
    console.log('connection error',err, err.stack); // an error occurred
    else{   
      //console.log(data);           // successful response
      if(data['Messages']){
        rh = data['Messages'][0]['ReceiptHandle'];
        pg.connect(conString, function(err, client, done) {
          if(err) {
            return console.error('could not connect to postgres', err);
          }else{
            client.query('SELECT * from emp', function(err, result) {
              if(err){
                console.log(err);
              }else{
                rows = result.rows;
                for(var i = 0; i < rows.length; i++){
                  var params = {
                    TableName:"employees",
                    Item:{
                      "id" : rows[i].firstname + rows[i].lastname,
                      "firstname": rows[i].firstname, 
                      "lastname":rows[i].lastname,
                      "age":  rows[i].age
                      }
                  };
                  putItem(params);  
                  if( i === rows.length - 1 ){
                    client.query('delete from emp', function (err){
                      deleteMessage(rh);
                    });
                    done();
                  }
                }

              }
            });
          }
        });
      }else{
        readMessage();
      }
    }
  });
}

function putItem(params,retry){
  if(retry === undefined){
    retry = 1;
  }else{
    retry++;
  }
  docClient.put(params, function(err, data) {
    if (err) {
      console.error(" Unable to add row Error JSON:", JSON.stringify(err, null, 2));
      if (err.statusCode == 400){
        if(retry < 3){
          console.log("retrying");
          setTimeout(putItem,100,[params,retry]);
        }
      }
    } 
  });
}

function deleteMessage(rh){
  sqs.deleteMessage( { QueueUrl : queue, ReceiptHandle: rh }, function(err,data){
    if(err){
      console.log(err);
      deleteMessage(rh);
    }else{
      readMessage();
    }
  });
}


readMessage();
