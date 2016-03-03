<?php

namespace AppBundle\Controller;

use Sensio\Bundle\FrameworkExtraBundle\Configuration\Route;
use Symfony\Bundle\FrameworkBundle\Controller\Controller;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response as Response;

class DefaultController extends Controller
{
  /**
   * @Route("/", name="homepage")
   */
  public function indexAction(Request $request)
  {
    // replace this example code with whatever you need
    return $this->render('default/index.html.twig', [
      'base_dir' => realpath($this->getParameter('kernel.root_dir').'/..'),
        ]);
  }
  /**
   * @Route("/setup", name="setup")
   */

  public function setupAction(Request $request){
    $client = new \Aws\DynamoDb\DynamoDbClient([
      'region'  => 'us-east-1',
      'version' => 'latest',
      ]);
    $result = $client->listTables();
    $msg = "";
    if(sizeof($result['TableNames']) == 0){
      /*$result = $client->createTable(array(
        'TableName' => 'jobs',
        'AttributeDefinitions' => array(
          array(
            'AttributeName' => 'name',
            'AttributeType' => 'S'
          )
        ),
        'KeySchema' => array(
          array(
            'AttributeName' => 'name',
            'KeyType'       => 'HASH'
          )
        ),
        'ProvisionedThroughput' => array(
          'ReadCapacityUnits'  => 1,
          'WriteCapacityUnits' => 1
        )
      ));
      //$pid = $process->getPid();*/
      $sqs = new \Aws\Sqs\SqsClient([
        'version' => 'latest',
        'region'  => 'us-east-1'
        ])
      $sqs->sendMessage(array('MessageBody' => 'setup', 'QueueUrl' => $this->getParameter('jobq')));

      $msg = "In-Progress";//.$pid;
    }else{
      $result = $client->getItem(array(
        'ConsistentRead' => true,
        'TableName' => 'jobs',
        'Key'       => array(
          'name'   => array('S' => 'setup'),
        )
      ));
      $msg = $result['Item']['status']['S'];

    }
    $response = new Response(json_encode(array('status' => $msg)));
    $response->headers->set('Content-Type', 'application/json');

    return $response;

    /*return $this->render('default/setup.html.twig', [
      'setup_items' => array(),
    ]);*/
  }
  /**
   * @Route("/transfer", name="transfer")
   */


  public function transferAction(Request $request){
    $client = new \Aws\DynamoDb\DynamoDbClient([
      'region'  => 'us-east-1',
      'version' => 'latest',
      ]);

    $result = $client->getItem(array(
      'ConsistentRead' => true,
      'TableName' => 'jobs',
      'Key'       => array(
        'name'   => array('S' => 'transfer'),
      )
    ));
    $msg = $result['Item']['status']['S'];
    if($msg == null) {

      $sqs = new \Aws\Sqs\SqsClient([
        'version' => 'latest',
        'region'  => 'us-east-1'
        ]);
      $result = $client->putItem(array(
        'TableName' => 'jobs',
        'Item' => array(   'name' => array('S' => 'transfer') , 'status' => array('S' => 'In Progress'))));

      $sqs->sendMessage(array('MessageBody' => 'An awesome message!', 'QueueUrl' => $this->getParameter('transferq')));
      $msg = "In-Progress";
    }else{
      if($msg == "completed"){
        $result = $client->deleteItem(array(
          'TableName' => 'jobs',
          'Key' => array(   'name' => array('S' => 'transfer'))));
      }

    }
    $response = new Response(json_encode(array('status' => $msg)));
    $response->headers->set('Content-Type', 'application/json');

    return $response;
  }

  /**
   * @Route("/teardown", name="teardown")
   */

  public function teardownAction(Request $request){
    $client = new \Aws\DynamoDb\DynamoDbClient([
      'region'  => 'us-east-1',
      'version' => 'latest',
      ]);
    $result = $client->listTables();
    $msg = "";
    if(sizeof($result['TableNames']) == 0){

      $msg = "teardown completed";
    }else{


      $result = $client->getItem(array(
        'ConsistentRead' => true,
        'TableName' => 'jobs',
        'Key'       => array(
          'name'   => array('S' => 'teardown'),
        )
      ));
      if(empty($result['Item'])){
        $result = $client->getItem(array(
          'ConsistentRead' => true,
          'TableName' => 'jobs',
          'Key'       => array(
            'name'   => array('S' => 'setup'),
          )
        ));

        $setup = $result['Item']['status']['S'];
        if($setup == "completed"){
          $msg = "In-Progress";
          $sqs = new \Aws\Sqs\SqsClient([
            'version' => 'latest',
            'region'  => 'us-east-1'
            ]);
          $sqs->sendMessage(array('MessageBody' => 'teardown', 'QueueUrl' => $this->getParameter('jobq')));
        }
      }else{
        $msg = $result['Item']['status']['S'];
      }
    }

    $response = new Response(json_encode(array('status' => $msg)));
    $response->headers->set('Content-Type', 'application/json');

    return $response;

  }
  /**
   * @Route("/count", name="count")
   */

  public function countAction(Request $request){
    $client = new \Aws\DynamoDb\DynamoDbClient([
      'region'  => 'us-east-1',
      'version' => 'latest',
      ]);
    $result = $client->scan([
      'AttributesToGet' => ['id'],
      'ConsistentRead' =>  true,
      'TableName' => 'employees'] 
    );	
    $response = new Response(json_encode(array('count' => $result['Count'])));
    $response->headers->set('Content-Type', 'application/json');

    return $response;

  }
  /**
   * @Route("/takedown", name="takedown")
   */

  public function takedownAction(Request $request){
    $client = new \Aws\Ec2\Ec2Client([
      'region'  => 'us-east-1',
      'version' => 'latest',
      ]);

    $result = $client->DescribeInstances(array(
      'Filters' => array(
        array('Name' => 'image-id', 'Values' => array($this->getParameter('postgresimg'))),
      )
    ));
    $instance_id = null;
    if(! empty($result['Reservations']) && ! empty($result['Reservations'][0]['Instances'])){
      $instance_id = $result['Reservations'][0]['Instances'][0]['InstanceId'];
      if($instance_id !== null){
        $result = $client->terminateInstances(['InstanceIds' => [$instance_id]]);
      }
    }
    $response = new Response(json_encode(array('status' => 'done')));
    $response->headers->set('Content-Type', 'application/json');

    return $response;

  }


}
