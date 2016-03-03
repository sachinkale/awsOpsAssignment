#!/usr/bin/ruby
require 'aws-sdk'
require 'json'
require '/home/ec2-user/params.rb'
require 'base64'
#
Aws.config.update({region: 'us-east-1'})


def setup
  dbclient = Aws::DynamoDB::Client.new(region: 'us-east-1')
  dynamoDB = Aws::DynamoDB::Resource.new(client: dbclient)
  if dynamoDB.tables.any?
    dynamoDB.tables.each do |t|
      if(t.name == "jobs")
        sleep 5
        dbclient.put_item({
          table_name: "jobs",
          item:
          {
          "name" => "setup",
          "status" =>  "In Progress"
        }
        })
      end
    end
  else
    table = dynamoDB.create_table({
      table_name: "jobs",
      attribute_definitions: [
        {
      attribute_name: "name",
      attribute_type: "S"
    }
    ],
      key_schema: [
        {
      attribute_name: "name",
      key_type: "HASH",
    }
    ],
      provisioned_throughput: {
      read_capacity_units: 1,
      write_capacity_units: 1,
    },

    })

    dynamoDB.client.wait_until(:table_exists, table_name:'jobs')
    table = dynamoDB.table('jobs')
    dbclient.put_item({
      table_name: "jobs",
      item:
      {
      "name" => "setup",
      "status" =>  "In Progress"
    }
    })



  end

  #create emp table
  table = dynamoDB.create_table({
    table_name: "employees",
    attribute_definitions: [
      {
    attribute_name: "id",
    attribute_type: "S"
  }
  ],
    key_schema: [
      {
    attribute_name: "id",
    key_type: "HASH",
  }
  ],
    provisioned_throughput: {
    read_capacity_units: DYNDB_READ_CAP,
    write_capacity_units: DYNDB_WRITE_CAP ,
  },

  })

  #begin
  #create postgres nodes
  client = Aws::EC2::Client.new(region: 'us-east-1')
  ec2 = Aws::EC2::Resource.new(client: client)

  #create node1
  node1 = ec2.create_instances({
    image_id: POSTGRES_IMG,
    min_count: 1,
    max_count: 1,
    instance_type: POSTGRES_INSTANCE_TYPE, 
    subnet_id: SUBNET_IDS[0],
    security_group_ids: [POSTGRES_SG_ID],
    key_name: KEY
  })
  pgnode1 = node1[0]
  pgnode1.create_tags({
    tags: [ # required
      {
    key: "Name",
    value: "pgnode1",
  },
  ],
  })
  #create node2 in different availability zone 
  node2 = ec2.create_instances({
    image_id: POSTGRES_IMG,
    min_count: 1,
    max_count: 1,
    instance_type: POSTGRES_INSTANCE_TYPE, 
    subnet_id: SUBNET_IDS[1],
    security_group_ids: [POSTGRES_SG_ID],
    key_name: KEY
  })

  pgnode2 = node2[0]

  pgnode2.create_tags({
    tags: [ # required
      {
    key: "Name",
    value: "pgnode2",
  },
  ],
  })

  pgnode2.wait_until_running

  #construct user data for worker nodes
  userdata = { 
    :AWSQURL => AWSQURL, 
    :AWSTQURL =>  AWSTQURL, 
    :pgnode1 => pgnode1.private_ip_address, 
    :pgnode2 => pgnode2.private_ip_address,
    :GITURL => GITURL
  }

  # create worker instances
  #rescue Aws::EC2::Errors::ServiceError
  as_client = Aws::AutoScaling::Client.new(region: 'us-east-1')
  autoscaling = Aws::AutoScaling::Resource.new(client: as_client)

  lc = autoscaling.create_launch_configuration({
    launch_configuration_name: "workerLC", # required
    image_id: WORKER_IMG,
    key_name: KEY,
    instance_type: WORKER_INSTANCE_TYPE,
    security_groups: [WORKER_SG_ID],
    user_data: Base64.encode64(userdata.to_json),
    iam_instance_profile: IAM_WORKER_PROFILE,
    associate_public_ip_address: true,
  })

  asg = autoscaling.create_group({
    auto_scaling_group_name: "workerASG", # required
    launch_configuration_name: "workerLC",
    min_size: 2, # required
    max_size: 4, # required
    desired_capacity: 2,
    default_cooldown: 1,
    vpc_zone_identifier: "subnet-2044cb56,subnet-35dc001f",
    health_check_type: "EC2",
    health_check_grace_period: 1,
    tags: [
      {
    resource_id: "workerASG",
    resource_type: "auto-scaling-group",
    key: "Name", # required
    value: "worker",
    propagate_at_launch: true,
  },
  ],
  })
  loop do
    resp = as_client.describe_auto_scaling_groups()
    sleep 10
    puts "waiting"
    if ! resp[0].to_s.match(/lifecycle_state=\"InService\"/).nil?
      break
    end
  end
  scaleup = asg.put_scaling_policy({
    policy_name: "scaleup", # required
    adjustment_type: "ChangeInCapacity", # required
    scaling_adjustment: 1,
    cooldown: 300,
  })
  scaledown =  asg.put_scaling_policy({
    policy_name: "scaledown", # required
    adjustment_type: "ChangeInCapacity", # required
    scaling_adjustment: -1,
    cooldown: 300,
  })

  puts scaleup.policy_arn        
  cloudwatch = Aws::CloudWatch::Client.new
  cloudwatch.put_metric_alarm({
    alarm_name: "AddCapacityToProcessQ", # required
    alarm_description: "Queue messages are above threshold",
    actions_enabled: true,
    alarm_actions: [scaleup.policy_arn],
    metric_name: "ApproximateNumberOfMessagesVisible", # required
    namespace: "AWS/SQS", # required
    statistic: "Average", # required, accepts SampleCount, Average, Sum, Minimum, Maximum
    dimensions: [
      {
    name: "QueueName", # required
    value: TESTQ
  },
  ],
  period: 300, # required
  unit: "Seconds",
  evaluation_periods: 1, # required
  threshold: 3000, # required
  comparison_operator: "GreaterThanOrEqualToThreshold", # required, accepts GreaterThanOrEqualToThreshold, GreaterThanThreshold, LessThanThreshold, LessThanOrEqualToThreshold
  })

  cloudwatch.put_metric_alarm({
    alarm_name: "RemoveCapacityToProcessQ", # required
    alarm_description: "Queue messages are above threshold",
    actions_enabled: true,
    alarm_actions: [scaledown.policy_arn],
    metric_name: "ApproximateNumberOfMessagesVisible", # required
    namespace: "AWS/SQS", # required
    statistic: "Average", # required, accepts SampleCount, Average, Sum, Minimum, Maximum
    dimensions: [
      {
    name: "QueueName", # required
    value: TESTQ
  },
  ],
  period: 300, # required
  unit: "Seconds", 
  evaluation_periods: 1, # required
  threshold: 3000, # required
  comparison_operator: "LessThanOrEqualToThreshold", # required, accepts GreaterThanOrEqualToThreshold, GreaterThanThreshold, LessThanThreshold, LessThanOrEqualToThreshold
  })

  if dynamoDB.tables.any?
    dynamoDB.tables.each do |t|
      if(t.name == "jobs")
        sleep 5
        dbclient.put_item({
          table_name: "jobs",
          item:
          {
          "name" => "setup",
          "status" =>  "completed"
        }
        })
      end
    end
  end
end


def teardown
  dbclient = Aws::DynamoDB::Client.new(region: 'us-east-1')
  dynamoDB = Aws::DynamoDB::Resource.new(client: dbclient)

  if dynamoDB.tables.any?
    dynamoDB.tables.each do |t|
      if(t.name == "jobs")
        dbclient.put_item({
          table_name: "jobs",
          item:
          {
          "name" => "teardown",
          "status" =>  "In Progress"
        }
        })
      end
    end
  end

  as_client = Aws::AutoScaling::Client.new(region: 'us-east-1')


  as_client.delete_auto_scaling_group({
    auto_scaling_group_name: "workerASG", # required
    force_delete: true,
  })
  as_client.delete_launch_configuration({
    launch_configuration_name: "workerLC"
  })

  loop do
    resp = as_client.describe_auto_scaling_groups()
    if resp[0].empty?
      break
    end
    sleep 5
  end

  client = Aws::EC2::Client.new(region: 'us-east-1')
  ec2 = Aws::EC2::Resource.new(client: client)

  ec2.instances.each do |i|
    if i.image_id ==  POSTGRES_IMG
      i.terminate()
    end
  end
  cloudwatch = Aws::CloudWatch::Client.new()
  cloudwatch.delete_alarms({
    alarm_names: ["AddCapacityToProcessQ","RemoveCapacityToProcessQ"] # required
  })

  if dynamoDB.tables.any?
    dynamoDB.tables.each do |t|
      t.delete()
    end
  end
end

poller = Aws::SQS::QueuePoller.new(JOBS_Q)
poller.poll do |msg|
  if msg.body == "setup"
    setup
  else
    teardown
  end
  poller.delete_message(msg)
end

