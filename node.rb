require 'socket'
require 'open3'
require 'csv'
require 'thread'
#require '/rgl-master/lib/rgl/adjacency'
require 'dijkstra/dijkstra'
require 'dijkstra/node'
require 'dijkstra/edge'
require 'dijkstra/graph'
require 'json'

$port = nil
$hostname = nil
$file_data = Hash.new
#Also https://en.wikipedia.org/wiki/Link-state_routing_protocol#Distributing_maps
$rout_tbl = Hash.new
#$neighbors = Hash.new # Stores only neighbors

$connections = Hash.new # stores open tcpconnections by dst node name

$nodes = Hash.new # Stores Node object by name for use with $topography
$server = nil
#$sockfd = nil
#Note: May not be necessary
$mutex = Mutex.new

$sequence_number = 0 # for link state

$topography = Graph.new # local graph of topography


# --------------------- Part 0 --------------------- # 

def server_init()
  $server = TCPServer.new $port.to_i
  loop {
    Thread.start($server.accept) do |client|
      print "Connected"

      line = client.gets.chomp
      if line.include? "EDGEB"
        line = (line + " 1\n").strip()
        arr = line.split(' ')
        edgeb(arr[1..4])
      elsif line.include? "LINKSTATE"
        #TODO: Things here to do with updating tables. Remember to parse on tab. And figure out json
        arr = line.split("\t")
        #get hash of neighbors and weights of sender
        linkstate_hash = JSON.parse(arr.last)
        # get sender and sender sequence number
        sender = arr[1]
        sender_seq_num = arr[2].to_i
        if sender_seq_num != $rout_tbl['sender'][2]
          update_topography(linkstate_hash,sender_seq_num,sender,line + "\n")
        end
      end

    end
  }
end


def edgeb(cmd)
  #TODO Test if this still works
  # HAS NOT BEEN TESTED
  ################################
  $mutex.synchronize do
    # update routing table, neighbors, and topography
    $rout_tbl[cmd[2]] = [cmd[1],1,-1]
    $nodes[cmd[2]] = Node.new(cmd[2])
    $topography.add_node($nodes[cmd[2]])
    $topography.add_edge($nodes[$hostname],$nodes[cmd[2]],1)

  end
  #################################
  # Store new connection in hash
  unless $connections.has_key?(cmd[2])
    $connections[cmd[2]] = TCPSocket.new cmd[1], $file_data[cmd[2]]
  end
  if cmd.length < 4
    #$sockfd = TCPSocket.new cmd[1], $file_data[cmd[2]]
    #$connections[cmd[2]] = TCPSocket.new cmd[1], $file_data[cmd[2]]
    to_send = "EDGEB " + cmd[1] + " " + cmd[0] + " " + $hostname + "\n"
    #$sockfd.puts to_send
    $connections[cmd[2]].puts to_send
    #$sockfd.close
  end
   

end

def dumptable(cmd)
  
  f = File.open(cmd[0][2..-1],"w")
  $rout_tbl.each do |key, array|
    f.write("#{$hostname}" + ",#{key}" + ",#{key}" + ",#{array[1]}")
  end

end

def shutdown(cmd)
  STDOUT.close
  STDIN.close
  STDERR.close
  # kill listener
  if $server
    $server.close
  end
  # kill open connections
  $connections.each do |key, connection|
    connection.close
  end
  #STDOUT.puts "SHUTDOWN: not implemented"
  exit(0)
end



# --------------------- Part 1 --------------------- #

def update_topography(link_state_hash, seq_number, sender,mesg)
  #TODO update sequence number
  #TODO update $topography with edges from sender to link_state_hash
  #TODO pass link_state_mssg to neighbors
  #TODO Dijkstras
  #TODO Update routing table
  # Update local sequence number for sender
  $rout_tbl['sender'][2] = seq_number
  # add sender to $nodes if not present
  unless $nodes.has_key?(sender)
    $nodes[sender] = Node.new(sender)
  end
  # update topography
  link_state_hash.each do |key,value|
    unless $nodes.has_key?(key)
      $nodes[key] = Node.new(key)
    end
    unless $topography.has_node?($nodes[key])
      $topography.add_node($nodes[key])
    end

    $topography.add_edge($nodes['sender'],nodes[key],value[1])
  end

  send_along_link_state(mesg)

end

# Pass on link state message rather than create it
def send_along_link_state(mesg)
  $connections.each do |key, connection|
    connection.puts mesg
  end
end

# Send link state update to all neighbors
def send_link_state()
  #create and populate hash of neighbors to send with link state message
  neighbors = Hash.new()
  $connections.each do |key,connection|
    #first and second element of array into neighbors hash
      neighbors[key] = $rout_tbl[key][0,1]
  end
  to_send = "LINKSTATE" + "\t" + "#{$hostname}" + "\t" + "#{$sequence_number}"  + "\t" + "#{neighbors.to_json}" + "\n"
  $connections.each do |key,connection|
    connection.puts to_send
  end
  $sequence_number+=1
end

#Both edged and edgeu need to call send_link_state
def edged(cmd)
	STDOUT.puts "EDGED: not implemented"
end

def edgeu(cmd)
	STDOUT.puts "EDGEU: not implemented"
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
		when "EDGEU"; edgeu(args)
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
  $nodes[$hostname] = Node.new($hostname)
  $topography.add_node($nodes[$hostname])
  Thread.new do 
    server_init 
  end

  main()

end

setup(ARGV[0], ARGV[1])





