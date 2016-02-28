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

    return $this->render('default/setup.html.twig', [
            'setup_items' => array(),
        ]);
    }
    /**
     * @Route("/transfer", name="transfer")
     */


    public function transferAction(Request $request){

	    $sqs = new \Aws\Sqs\SqsClient([
		            'version' => 'latest',
			    'region'  => 'us-east-1'
	    ]);
            $sqs->sendMessage(array('MessageBody' => 'An awesome message!', 'QueueUrl' => 'https://sqs.us-east-1.amazonaws.com/093840616381/transferq'));
	    $response = new Response(json_encode(array('name' => 'sachin')));
	    $response->headers->set('Content-Type', 'application/json');

	    return $response;
    }
}
