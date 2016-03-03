#!/usr/bin/ruby

require 'net/http'
require 'json'

uri = URI("http://169.254.169.254/latest/user-data")
res = Net::HTTP.get_response(uri)
str = JSON.parse!(res.body)

system(%Q[echo "#{str['pgnode1']} pgnode1" >> /etc/hosts])
system(%Q[echo "#{str['pgnode2']} pgnode2" >> /etc/hosts])

system(%Q[echo 'AWSQURL=#{str["AWSQURL"]}' >> /home/ec2-user/worker-env])
system(%Q[echo 'AWSTQURL=#{str["AWSTQURL"]}' >> /home/ec2-user/worker-env])
system("echo 'NODE_PATH=/home/ec2-user/node_modules' >> /home/ec2-user/worker-env")

Dir.chdir("/home/ec2-user")
system("/usr/bin/pgpool")
system("git clone #{str['GITURL']} repo")
system("cp /home/ec2-user/repo/workers/*-worker.js /home/ec2-user/")
system("chown ec2-user:ec2-user -R /home/ec2-user")
system("/usr/bin/ruby /usr/local/bin/god -c /home/ec2-user/worker.god -l /home/ec2-user/god.log")
