God.pid_file_directory = "/tmp"
God.watch do |w|
  w.name = "transfer"
  w.group = "workers"
  contents = File.readlines('/home/ec2-user/worker-env')
  env_h = Hash.new
  contents.each do |c|
    if c != ''
      a = c.split('=')
      env_h[a[0]] = a[1].chomp
    end
  end
  w.env = env_h
  w.start = "/usr/bin/node /home/ec2-user/transfer-worker.js"
  w.log = "/home/ec2-user/transfer.log"
  w.keepalive
end
God.watch do |w|
  w.name = "fill"
  w.group = "workers"
  contents = File.readlines('/home/ec2-user/worker-env')
  env_h = Hash.new
  contents.each do |c|
    if c != ''
      a = c.split('=')
      env_h[a[0]] = a[1].chomp
    end
  end
  w.env = env_h
  w.start = "/usr/bin/node /home/ec2-user/fill-worker.js"
  w.log = "/home/ec2-user/fill.log"
  w.keepalive
end

