var AWS = require("aws-sdk");
var pg = require('pg');

var queue = process.env.AWSTQURL;
var sqs = new AWS.SQS({ region: 'us-east-1'});
var params = {
  QueueUrl : queue,
  WaitTimeSeconds : 10
}

var putcount = 0;
var rowcount = 0;
var conString = "postgres://postgres:@localhost:9999/postgres";
AWS.config.update({
  region: 'us-east-1',
});
var rh = null;
var docClient = new AWS.DynamoDB.DocumentClient();

function readMessage(){
  sqs.receiveMessage(params, function(err, data) {
    if (err) 
    console.log('connection error',err, err.stack); // an error occurred
    else{   
      //console.log(data);           // successful response
      if(data['Messages']){
        rowcount  =0;
        putcount = 0;
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
                rowcount = rows.length;
                if(rowcount == 0){
                  waitforme();
                }else{
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
                        waitforme();
                      });
                      done();
                    }
                  }}

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
      if (err.statusCode == 400 || err.retryable == "true"){
        if(retry < 3){
          console.log("retrying");
          setTimeout(putItem,100,[params,retry]);
        }else{
          rowcount--;
        }
      }


    }else{

      putcount++;
    } 
  });
}

function waitforme(){
  if(putcount == rowcount){
    deleteMessage();	
  }else{
    console.log(rowcount,putcount);
    setTimeout(waitforme,100);

  }


}

function deleteMessage(){
  sqs.deleteMessage( { QueueUrl : queue, ReceiptHandle: rh }, function(err,data){
    if(err){
      console.log(err);
      deleteMessage();
    }else{
      var params = {
        TableName:"jobs",
  Item:{
    "name" : "transfer",
  "status": "completed"
  }
      };

      docClient.put(params, function(err, data) {
        if(err)
        console.log(err);
      });
      readMessage();
    }
  });
}


readMessage();
