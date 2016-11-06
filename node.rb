require 'socket'
require 'open3'


$port = nil
$hostname = nil
$file_data = Hash.new
$rout_tbl = Hash.new



# --------------------- Part 0 --------------------- # 

def server_init()
  server = TCPServer.new $port.to_i
  loop do
   client = server.accept    # Wait for a client to connect
    print "Connected"
    line = client.gets.chomp + " 1\n"
    line = line.strip()
    arr = line.split(' ')
    edgeb(arr[1..4])
  # first_stdin, wait_thr = Open3.pipeline_w(result)
   client.close
  end
end


def edgeb(cmd)
  
  $rout_tbl[cmd[2]] = [cmd[1],1]
  print cmd
  if cmd.length < 4
    sockfd = TCPSocket.new cmd[1], $file_data[cmd[2]]
    to_send = "EDGEB " + cmd[1] + " " + cmd[0] + " " + $hostname + "\n"
    sockfd.puts to_send
    sockfd.close 
  end
   

end

def dumptable(cmd)
	puts "DUMPTABLE: not implemented"
end

def shutdown(cmd)
	STDOUT.puts "SHUTDOWN: not implemented"
	exit(0)
end



# --------------------- Part 1 --------------------- # 
def edged(cmd)
	STDOUT.puts "EDGED: not implemented"
end

def edgew(cmd)
	STDOUT.puts "EDGEW: not implemented"
end

def status()
	STDOUT.puts "STATUS: not implemented"
end


# --------------------- Part 2 --------------------- # 
def sendmsg(cmd)
	STDOUT.puts "SENDMSG: not implemented"
end

def ping(cmd)
	STDOUT.puts "PING: not implemented"
end

def traceroute(cmd)
	STDOUT.puts "TRACEROUTE: not implemented"
end

def ftp(cmd)
	STDOUT.puts "FTP: not implemented"
end




# do main loop here.... 
def main()
  
  
  

  while(line = STDIN.gets())
   
		line = line.strip()
		arr = line.split(' ')
		cmd = arr[0]
		args = arr[1..-1]
		case cmd
		when "EDGEB"; edgeb(args)
		when "EDGED"; edged(args)
		when "EDGEW"; edgew(args)
		when "DUMPTABLE"; dumptable(args)
		when "SHUTDOWN"; shutdown(args)
		when "STATUS"; status()
		when "SENDMSG"; sendmsg(args)
		when "PING"; ping(args)
		when "TRACEROUTE"; traceroute(args)
		when "FTP"; ftp(args)
		else STDERR.puts "ERROR: INVALID COMMAND \"#{cmd}\""
		end
	end

end

def setup(hostname, port)

  File.open(ARGV[2], 'r') do |file|
    file.each_line do |line|
      line_data = line.split(',')
      $file_data[line_data[0]] = line_data[1].chomp.to_i
    end
  end

  $hostname = hostname
  $port = port
  
  #set up ports, server, buffers
  
  Thread.new do 
    server_init 
  end

  main()

end

setup(ARGV[0], ARGV[1])





