require 'socket'
require 'open3'
require 'csv'
require 'thread'
require 'yaml'

#require '/rgl-master/lib/rgl/adjacency'
require_relative 'dijkstra/dijkstra'
require_relative 'dijkstra/graph_node'
require_relative 'dijkstra/edge'
require_relative 'dijkstra/graph'
require_relative 'packet'
require 'json'

$port = nil
$hostname = nil
$file_data = Hash.new
$updateInterval = nil
$maxPayload = nil
$pingTimeout = nil
$packet_buffer = []
$buffered_packets = 0
$ID_counter = 0
$ping_responses = []
#Also https://en.wikipedia.org/wiki/Link-state_routing_protocol#Distributing_maps
$mutex = Mutex.new
$rout_tbl = Hash.new
#$neighbors = Hash.new # Stores only neighbors
$seq_number = Hash.new

$connections = Hash.new # stores open tcpconnections by dst node name

$nodes = Hash.new # Stores Node object by name for use with $topography
$server = nil
#$sockfd = nil
#Note: May not be necessary


$sequence_number = 0 # for link state

$topography = Graph.new # local graph of topography
$dijkstra = nil # dijkstra class

$time = 0 #Stores the time of the last update

$queue = []

$threads = []

# --------------------- Part 0 --------------------- #

def server_init()
  $server = TCPServer.new $port.to_i
  loop {
    $threads << Thread.start($server.accept) do |client|
      loop {
        line = client.gets.chomp
        $queue.push(line)
      }
    end
  }
end

def queue_loop()
    loop {
      if $queue.length > 0
        #puts "++++++++++++++++++++++"
        #puts $queue
        line = ""
        $mutex.synchronize do
          line = $queue.shift
        #puts line
        end
        STDOUT.puts line
        STDOUT.puts "+++++++++++++++++++++++++++++"
        if line.include? "EDGEB "
          #puts "EDGEB"
          line = (line + " 1\n").strip()
          arr = line.split(' ')
          #puts arr[1..4]
          #$mutex.synchronize do
          edgeb(arr[1..4])
          #end
          #edgeb(arr)
        elsif line.include? "LINKSTATE"
          #puts "Server recieved linkstate message: "
          arr = line.split("\t")
          #get hash of neighbors and weights of sender
          linkstate_hash = JSON.parse(arr.last)
          # get sender and sender sequence number
          sender = arr[1]
          sender_seq_num = arr[2].to_i
          # Make sure actually have info for this node before accessing the hash
          #$mutex.synchronize do
          if (not $seq_number.has_key?(sender)) or sender_seq_num != $seq_number[sender]
            update_topography(linkstate_hash,sender_seq_num,sender,line + "\n")
          end
        elsif line.include? "DUMPTABLE"
          arr = line.split(' ')
          cmd = arr[0]
          args = arr[1..-1]
          dumptable(args,true)

        elsif line.include? "EDGEBLOCAL"
          arr = line.split(' ')
          cmd = arr[0]
          args = arr[1..-1]
          edgeb(args,true)

        elsif line.include? "SENDLSTATE"
          #puts "test"
          send_link_state()

        elsif line.include? "MSG"
          arr = line.split("\t")
          packet = Packet.new
          packet.from_json! arr.last
          dst = packet.header["dst"]
          src = packet.header["src"]

          if packet.header["ping"] == true
            #puts "============================"
            if packet.header["ping_src"] == $hostname
              
              $ping_responses[packet.header["seq_num"]] = 1
              
              start = packet.header["sent_time"].split("\s")
              date = start[0].split("-")
              time = start[1].split(":")
              zone = start[2][0..2] + ":" + start[2][3..4]
              sent_time = Time.new(date[0].to_i,date[1].to_i,date[2].to_i, 
                               time[0].to_i,time[1].to_i,time[2].to_i,
                               zone)
              finish = Time.now
              rtt =  finish - sent_time
              STDOUT.puts "#{packet.header["seq_num"]} #{src} #{rtt}"
              
            elsif dst == $hostname
              response_ping = Packet.new
              response_ping.header["dst"] = src
              response_ping.header["src"] = dst
              response_ping.header["ping"] = true
              response_ping.header["ping_src"] = src
              response_ping.header["sent_time"] = packet.header["sent_time"]
              response_ping.header["seq_num"] = packet.header["seq_num"]
              
              if $rout_tbl.has_key?(src)
                
                next_hop = $rout_tbl[src][0].name #next_hop router name
                to_send = "MSG" + "\t" + "#{response_ping.to_json}" + "\n"
                $connections[next_hop].puts to_send
              end
              
            else
              
              if $rout_tbl.has_key?(dst)
                next_hop = $rout_tbl[dst][0].name #next_hop router name
                to_send = "MSG" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
              end
            end
          elsif packet.header["fail"] == true
            
            if dst == $hostname
              STDOUT.puts "SENDMSG ERROR: HOST UNREACHABLE"
            else
              if $rout_tbl.has_key?(dst)
                next_hop = $rout_tbl[dst][0].name #next_hop router name
                to_send = "MSG" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
              end
            end
          else
            
            dst = packet.header["dst"]
            src = packet.header["src"]
            id = packet.header["ID"]
            offset = packet.header["offset"]
            mf = packet.header["mf"]
            msg = packet.msg
            to_output = ""
            if dst == $hostname
              if mf == false
                iter = 0
                while $buffered_packets > 0
                  if $packet_buffer[iter]
                    to_output = to_output + $packet_buffer[iter].msg
                    iter = iter + $maxPayload
                    $buffered_packets = $buffered_packets - 1
                  end
                end
                to_output = to_output + msg
                STDOUT.puts "SENDMSG: #{src} --> #{to_output}"
              else
                if offset > 0 
                  if $packet_buffer[0].header["ID"] != id
                    #ID of current packet and buffered packets don't match
                  end
                else
                  $packet_buffer[offset] = packet
                  $buffered_packets = $buffered_packets + 1 
                end
              end
            
            else
              if $rout_tbl.has_key?(dst)
                next_hop = $rout_tbl[dst][0].name #next_hop router name
                to_send = "MSG" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
                
              else
                send_fail_packet(packet)
              end
            end
          end
        elsif line.include? "SENDMSG FAILURE"
          
          
        end
      end
      sleep(0.00001)
    }
end


def edgeb(cmd, bool=false)
  if bool
    # update routing table, neighbors, and topography
    $rout_tbl[cmd[2]] = [cmd[2],1]
    $seq_number[cmd[2]] = -1
    $mutex.synchronize do
      $nodes[cmd[2]] = Node.new(cmd[2])
      $topography.add_node($nodes[cmd[2]])
      $topography.add_edge($nodes[$hostname],$nodes[cmd[2]],1)
    end
    # Store new connection in hash
    #puts cmd[3]

    unless $connections.has_key?(cmd[2])
      $connections[cmd[2]] = TCPSocket.new cmd[1], $file_data[cmd[2]]
    end
    if cmd.length < 4
      #$sockfd = TCPSocket.new cmd[1], $file_data[cmd[2]]
      #$connections[cmd[2]] = TCPSocket.new cmd[1], $file_data[cmd[2]]
      to_send = "EDGEB " + cmd[1] + " " + cmd[0] + " " + $hostname + "\n"
      #$sockfd.puts to_send
      $connections[cmd[2]].puts to_send
      #puts to_send
      #$sockfd.close
      send_link_state
    end
  else
    $mutex.synchronize do
      $queue.push("EDGEBLOCAL " + cmd.join(" "))
    end
  end

end

def dumptable(cmd,bool=false)
  if bool
    f = File.open(cmd[0][2..-1],"w")

    $mutex.synchronize do
      $rout_tbl.each do |key, array|

        f.write("#{$hostname}" + ",#{key}" + ",#{key}" + ",#{array[1]}\n")
      end
    end
    f.close
  else
    $queue.push("DUMPTABLE " + cmd.join(" "))
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
#TODO Handle edge removal
def update_topography(link_state_hash, seq_number, sender, mesg)
  #TODO update sequence number
  #TODO update $topography with edges from sender to link_state_hash
  #TODO pass link_state_mssg to neighbors
  #TODO Dijkstras
  #TODO Update routing table
  # Update local sequence number for sender
  #IGNORE UNTIL FURTHER NOTICE#####NOTE THIS WILL NOT WORK IF $rout_tbl does not have entry for this yet.
  ######$rout_tbl['sender'][2] = seq_number
  #$mutex.synchronize do
    $seq_number[sender] = seq_number
    # add sender to $nodes if not present
    $mutex.synchronize do
      unless $nodes.has_key?(sender)
        $nodes[sender] = Node.new(sender)
      end
    end
    # update topography
    link_state_hash.each do |key,value|
      $mutex.synchronize do
        unless $nodes.has_key?(key)
          $nodes[key] = Node.new(key)
        end
      end
      $mutex.synchronize do
        unless $topography.has_node?($nodes[key])
          $topography.add_node($nodes[key])
        end
        $topography.add_edge($nodes[sender],$nodes[key],value[1])
      end
    end
    #Remove any edges that have been removed from the network from the local topography
    edges_l = $topography.get_edges_from_node($nodes[sender])
    edges_r = []
    link_state_hash.each do |key,value|
      edges_r.push(Edge.new($nodes[sender],$nodes[key],0))
      edges_r.push(Edge.new($nodes[key],$nodes[sender],0))
    end
    # puts edges_l[0] == edges_r[1]
    # puts edges_l
    # puts edges_r
    for elt in edges_l
      if not edges_r.include?(elt)
        $topography.remove_edge(elt.from,elt.to)
      end
    end
    # for edge in edges_res
    #   $topography.remove_edge(edge.from,edge.to)
    # end
 # end
  send_along_link_state(mesg)
  # $mutex.synchronize do  
  run_dijkstras()
  #end
end

# Pass on link state message rather than create it
def send_along_link_state(mesg)
  #$mutex.synchronize do
    $connections.each do |key, connection|
      connection.puts mesg
    end
  #end

end

#TODO 
# creates dijkstra object that contains all shortest paths and update routing table
def run_dijkstras()
    $mutex.synchronize do
    #puts $topography.edges
    fd = File.open($hostname + "test", "a")
    fd.puts "_________________________________"
    fd.puts $topography.edges
    fd.puts $nodes[$hostname]
    #fd.puts $nodes.keys
    #fd.puts $nodes.values
    $dijkstra = Dijkstra.new($topography, $nodes[$hostname])
    fd.puts "Djikstra done\n"
    fd.close
    end
    $mutex.synchronize do

    $nodes.each do |name, value|
        if name != $hostname
            path = $dijkstra.shortest_path_to(value)
            $rout_tbl[name] = [$dijkstra.shortest_path_to(value)[1],$dijkstra.distance_to[value]]
        end
      end
    end

  #end

end

# Send link state update to all neighbors
def send_link_state()
  #puts "sending link state"
  run_dijkstras
  #create and populate hash of neighbors to send with link state message
  #puts "dijkstras"
  neighbors = Hash.new()
  $connections.each do |key,connection|
    #first and second element of array into neighbors hash
    $mutex.synchronize do
      neighbors[key] = $rout_tbl[key]
    end
  end
  to_send = "LINKSTATE" + "\t" + "#{$hostname}" + "\t" + "#{$sequence_number}"  + "\t" + "#{neighbors.to_json}" + "\n"
  $connections.each do |key,connection|
    connection.puts to_send
  end
  $sequence_number+=1
end

#Both edged and edgeu need to call send_link_state
def edged(cmd)
  $topography.remove_edge($nodes[$hostname],$nodes[cmd[0]])
  $connections.delete(cmd[0])
  send_link_state
  
	#STDOUT.puts "EDGED: not implemented"
end

def edgeu(cmd)
  $topography.add_edge($nodes[$hostname],$nodes[cmd[0]],cmd[1].to_i)
  send_link_state
  
	#STDOUT.puts "EDGEU: not implemented"
end

def status()
  neighbors = []
  $connections.each do |key,connection|
    neighbors.push(key)
  end
  neighbors.sort!
  STDOUT.puts "Name: #{$hostname} Port: #{$port} Neighbors: #{neighbors.join(",")}"
end


# --------------------- Part 2 --------------------- #
def send_fail_packet(packet)
  fail_packet = Packet.new
  fail_packet.header["dst"] = packet.header["src"]
  fail_packet.header["src"] = $hostname
  fail_packet.header["fail"] = true
  if $connections.has_key?(packet.header["src"])
    to_send = "MSG" + "\t" + "#{fail_packet.to_json}" + "\n"
    $connections[packet.header["src"]].puts to_send
  end
end


def sendmsg(cmd)
  #STDOUT.puts "SENDMSG: not implemented"
  #cmd[0] = DST
  #cmd[1] = MSG
  err_flag = false
  payload = cmd[1]
  payload_len = payload.bytesize
  tracker = 0
  offset = 0
  while payload_len > $maxPayload || err_flag == true
    if $rout_tbl.has_key?(cmd[0])
      msg_packet = Packet.new
      msg_packet.header["dst"] = cmd[0] #sets dst header field
      msg_packet.header["src"] = $hostname
      msg_packet.header["len"] = $maxPayload #sets length header field
      msg_packet.header["ID"] = $ID_counter
      msg_packet.header["offset"] = offset
      msg_packet.header["mf"] = true
      msg_packet.msg = payload[tracker..(tracker + $maxPayload - 1)]
      puts msg_packet.msg
      tracker = tracker + $maxPayload
      payload_len = payload_len - $maxPayload
      offset = offset + $maxPayload
      next_hop = $rout_tbl[cmd[0]][0].name #next_hop router name
      to_send = "MSG" + "\t" + "#{msg_packet.to_json}" + "\n"
      $connections[next_hop].puts to_send
    else
      STDOUT.puts "SENDMSG ERROR: HOST UNREACHABLE"
      err_flag = true
    end
  end
  if payload_len > 0
    msg_packet = Packet.new
    msg_packet.header["dst"] = cmd[0] #sets dst header field
    msg_packet.header["src"] = $hostname
    msg_packet.header["len"] = payload_len #sets length header field
    msg_packet.header["ID"] = $ID_counter
    msg_packet.header["offset"] = offset + payload_len
    msg_packet.header["mf"] = false
    msg_packet.msg = payload[tracker..payload.bytesize]
    next_hop = $rout_tbl[cmd[0]][0].name #next_hop router name
    to_send = "MSG" + "\t" + "#{msg_packet.to_json}" + "\n"
    $connections[next_hop].puts to_send
  end
  $ID_counter = $ID_counter + 1
end

def check_timeout(seq_id)
  sleep $pingTimeout
  $mutex.synchronize do
    if $ping_responses[seq_id] == 0
      puts $ping_responses
      STDOUT.puts "PING ERROR: HOST UNREACHABLE (TIMEOUT)" 
    end
  end
end

def ping(cmd)
  #STDOUT.puts "PING: not implemented"
  #cmd[0] = DST
  #cmd[1] = NUMPINGS
  #cmd[2] = DELAY (between pings)
  dst = cmd[0]
  pings = cmd[1].to_i
  delay = cmd[2].to_i
  seq_id = 0
  ping_packet = Packet.new
  ping_packet.header["dst"] = dst
  ping_packet.header["src"] = $hostname
  ping_packet.header["ping"] = true
  ping_packet.header["ping_src"] = $hostname
  ping_packet.header["seq_num"] = seq_id
  $ping_responses[seq_id] = 0
  while pings > 0
    if $rout_tbl.has_key?(dst)
          
      next_hop = $rout_tbl[dst][0].name #next_hop router name
      ping_packet.header["sent_time"] = Time.now
      ping_packet.header["seq_num"] = seq_id
      to_send = "MSG" + "\t" + "#{ping_packet.to_json}" + "\n"
      $connections[next_hop].puts to_send
      Thread.new do
        check_timeout(seq_id)
      end
    else
      STDOUT.puts "PING ERROR: HOST UNREACHABLE"
    end
    pings = pings - 1
    seq_id = seq_id + 1
    sleep delay
    
  end


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
    if line.include? "check"
      puts $rout_tbl
    end
    if line.include? "test"
      if $hostname == "n1"
        if line.include? "test1"
          line = "EDGEB localhost localhost n2\n"
          line = line.strip()
          arr = line.split(' ')
          cmd = arr[0]
          args = arr[1..-1]
          edgeb(args)
        end
        if line.include? "test2"
          line = "EDGEB localhost localhost n3\n"
          line = line.strip()
          arr = line.split(' ')
          cmd = arr[0]
          args = arr[1..-1]
          edgeb(args)
        end

      end
      if $hostname == "n2"
        line = "EDGEB localhost localhost n3\n"
        line = line.strip()
        arr = line.split(' ')
        cmd = arr[0]
        args = arr[1..-1]
        edgeb(args)
      end
    else
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
        when "stats"; puts $topography.edges
        when "tbl"; puts $connections
      else STDERR.puts "ERROR: INVALID COMMAND \"#{cmd}\""
      end
    end

	end

end

def setup(hostname, port)
  
  config_str = begin
                     YAML.load_file('config')
                   end
  config_data = config_str.split("\s")
  $updateInterval = config_data[0][config_data[0].index("=")+1..-1].to_i
  $maxPayload = config_data[1][config_data[1].index("=")+1..-1].to_i
  $pingTimeout = config_data[2][config_data[2].index("=")+1..-1].to_i

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
  Thread.new do
    queue_loop
  end
  # Handle time
  $time = Time.now.to_i
  Thread.new do
    sleep 0.01
    $time += 0.01
  end
  Thread.new do
    
    loop {
      $mutex.synchronize do
        $queue.push("SENDLSTATE")
      end
      #send_link_state
      sleep $updateInterval
    }
  end
  main()
  
end

setup(ARGV[0], ARGV[1])





