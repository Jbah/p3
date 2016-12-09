# -*- coding: utf-8 -*-
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
$trace_responses = []
$trace_buffer = {}
$circuits = {}
$circuit_member = []
#Also https://en.wikipedia.org/wiki/Link-state_routing_protocol#Distributing_maps
$mutex = Mutex.new
$rout_tbl = Hash.new
#$neighbors = Hash.new # Stores only neighbors
$seq_number = Hash.new

$connections = Hash.new # stores open tcpconnections by dst node name

$local_nodes = Hash.new # Stores Node object by name for use with $topography
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
        $mutex.synchronize do
          $queue.push(line)
        end
      }
    end
  }
end

def queue_loop()
  #TODO IMPORTANT: IF IS FRAGMENT THAT DOESNT MATCH IP CURRENTLY BEING REASSEMBLED PUT BACK ON QUEUE AT ENDSEND
    loop {
      if $queue.length > 0
      #  puts "++++++++++++++++++++++"
      #  puts $rout_tbl
      #  puts $queue
        
        line = ""
        $mutex.synchronize do
          line = $queue.shift
        #puts line
        end
        # STDOUT.puts line
        # STDOUT.puts "+++++++++++++++++++++++++++++"
        if line.include? "EDGEB"
          #puts "EDGEB"
          line = (line + " 1\n").strip()
          arr = line.split(' ')
          #puts arr[1..4]
          # $mutex.synchronize do
          edgeb(arr[1..4],true)
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

        elsif line.include? "LEDGE"
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
<<<<<<< HEAD
       #   puts packet.to_json
=======
          puts packet.to_json
>>>>>>> a6ff7904a7529fd9cdfcc9dfaf3a853f427d1535
          dst = packet.header["dst"]
          src = packet.header["src"]
          if packet.header["trace"] == true
            path = packet.header["circ_path"]
            if packet.header["ping_src"] == $hostname
              hop_count = packet.header["seq_num"]
              time_to_node = packet.header["sent_time"]
              hostID = packet.header["src"]
              $trace_responses[hop_count] = 1 
              to_store = "#{hop_count} #{hostID} #{time_to_node}"
              $mutex.synchronize do
              if !$trace_buffer.has_key?(hop_count)
                $trace_buffer[hop_count] = to_store
              end
              end
            elsif packet.header["trace_response"] == true
              if path != nil
                next_node = path[path.index($hostname)-1]
                rout_cond = $rout_tbl.has_key?(next_node)
                next_hop = $rout_tbl[next_node][0]
              else
                rout_cond = $rout_tbl.has_key?(dst)
                next_hop = $rout_tbl[dst][0]
              end
              if rout_cond
                to_send = "MSG" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
              end
            else
              
              trace_response = Packet.new
              trace_response.header["dst"] = src
              trace_response.header["src"] = $hostname
              trace_response.header["trace"] = true
              trace_response.header["ping_src"] = packet.header["ping_src"]
              trace_response.header["seq_num"] = packet.header["seq_num"]
              trace_response.header["path_length"] = packet.header["path_length"]
              trace_response.header["trace_response"] = true
              trace_response.header["circ_path"] = path

              start = packet.header["sent_time"].split("\s")
              date = start[0].split("-")
              time = start[1].split(":")
              zone = start[2][0..2] + ":" + start[2][3..4]
              sent_time = Time.new(date[0].to_i,date[1].to_i,date[2].to_i, 
                               time[0].to_i,time[1].to_i,time[2].to_i,
                               zone)
              trace_response.header["sent_time"] = Time.now - sent_time
              
              if path != nil
                next_node1 = path[path.index($hostname)-1]
                rout_cond1 = $rout_tbl.has_key?(next_node1)
                next_hop1 = $rout_tbl[next_node1][0]
              else
                rout_cond1 = $rout_tbl.has_key?(src)
                next_hop1 = $rout_tbl[src][0]
              end
              if rout_cond1
                to_send = "MSG" + "\t" + "#{trace_response.to_json}" + "\n"
                $connections[next_hop1].puts to_send
              end

              if path != nil
                next_node2 = path[path.index($hostname)+1]
                rout_cond2 = $rout_tbl.has_key?(next_node2)
                next_hop2 = $rout_tbl[next_node2][0]
              else
                rout_cond2 = $rout_tbl.has_key?(dst)
                next_hop2 = $rout_tbl[dst][0]
              end
              if rout_cond2
                packet.header["seq_num"] = packet.header["seq_num"] + 1
                to_send = "MSG" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop2].puts to_send
              end
              
            end
          elsif packet.header["ping"] == true
            #puts "#{dst} : #{$rout_tbl}"
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
              path = packet.header["circ_path"]
              response_ping = Packet.new
              response_ping.header["dst"] = src
              response_ping.header["src"] = dst
              response_ping.header["ping"] = true
              response_ping.header["ping_src"] = src
              response_ping.header["sent_time"] = packet.header["sent_time"]
              response_ping.header["seq_num"] = packet.header["seq_num"]
              response_ping.header["circ_path"] = path

              if path != nil
                
                next_node = path[path.index($hostname)-1]
                rout_cond = $rout_tbl.has_key?(next_node)
                next_hop = $rout_tbl[next_node][0]
              else
                rout_cond = $rout_tbl.has_key?(src)
                next_hop = $rout_tbl[src][0]
              end
              if rout_cond
                to_send = "MSG" + "\t" + "#{response_ping.to_json}" + "\n"
                $connections[next_hop].puts to_send
              end
              
            else
              path = packet.header["circ_path"]
              if dst == packet.header["ping_src"] && path != nil
                next_node = path[path.index($hostname)-1]
                rout_cond = $rout_tbl.has_key?(next_node)
                next_hop = $rout_tbl[next_node][0]
              elsif dst != packet.header["ping_src"] && path != nil
                next_node = path[path.index($hostname)+1]
                rout_cond = $rout_tbl.has_key?(next_node)
                next_hop = $rout_tbl[next_node][0]
              else
                rout_cond = $rout_tbl.has_key?(dst)
                next_hop = $rout_tbl[dst][0]
              end
              if rout_cond
                to_send = "MSG" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
              end
            end
          elsif packet.header["fail"] == true
            if packet.header["ftp"] == true
              if dst == $hostname
                STDOUT.puts "FTP ERROR: #{packet.header["ftp_name"]} −− > #{packet.header["src"]} INTERRUPTED AFTER #{packet.header["offset"]*$maxPayload + packet.header["len"]}"
              else
                if $rout_tbl.has_key?(dst)
                  next_hop = $rout_tbl[dst][0] #next_hop router name
                  to_send = "MSG" + "\t" + "#{packet.to_json}" + "\n"
                  $connections[next_hop].puts to_send
                end
              end

            else
              #SENDMSG fail
              if dst == $hostname
                STDOUT.puts "SENDMSG ERROR: HOST UNREACHABLE"
              else
                if packet.header["circ_path"] != nil
                  path = packet.header["circ_path"]
                  next_node = path[path.index($hostname)+1]
                  rout_cond = $rout_tbl.has_key?(next_node)
                  next_hop = $rout_tbl[next_node][0]
                else
                  rout_cond = $rout_tbl.has_key?(dst)
                  next_hop = $rout_tbl[dst][0]
                end
                if rout_cond
                  to_send = "MSG" + "\t" + "#{packet.to_json}" + "\n"
                  $connections[next_hop].puts to_send
                end
              end
            end

          #TODO modify this to actually handle ftp
          elsif packet.header["ftp"]
            #puts "START FTP"
            dst = packet.header["dst"]
            src = packet.header["src"]
            id = packet.header["ID"]
            #puts "START FTP1"
            offset = packet.header["offset"]
            mf = packet.header["mf"]
            #puts "START FTP2"
            f_path = packet.header["ftp_path"]
            #puts "START FTP3"
            f_name = packet.header["ftp_name"]

            #puts f_path + "/" + f_name
            s = f_path + "/" + f_name
            file = File.open(s,'w')
            #puts "START FTP4"
            msg = packet.msg
            #puts "START FTP5"
            to_output = ""
            if dst == $hostname
              #puts "AT HOST"
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
                file.write(to_output)
                file.close()

              else
                if offset > 0
                  if $packet_buffer[0].header["ID"] != id
                    #ID of current packet and buffered packets don't match
                  end
                  $packet_buffer[offset] = packet
                  $buffered_packets = $buffered_packets + 1
                else
                  $packet_buffer[offset] = packet
                  $buffered_packets = $buffered_packets + 1
                end
              end

            else
              if packet.header["circ_path"] != nil
                path = packet.header["circ_path"]
                next_node = path[path.index($hostname)+1]
                rout_cond = $rout_tbl.has_key?(next_node)
                next_hop = $rout_tbl[next_node][0]
              else
                rout_cond = $rout_tbl.has_key?(dst)
                next_hop = $rout_tbl[dst][0]
              end
              if rout_cond
                to_send = "MSG" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send

              else
                send_fail_ftp_packet(packet)
              end
            end
          #Start of correct message handling
         #SENDMSG
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
                  $packet_buffer[offset] = packet
                  $buffered_packets = $buffered_packets + 1
                else
                  $packet_buffer[offset] = packet
                  $buffered_packets = $buffered_packets + 1
                end
              end
            
            else
              if packet.header["circ_path"] != nil
                path = packet.header["circ_path"]
                next_node = path[path.index($hostname)+1]
                rout_cond = $rout_tbl.has_key?(next_node)
                next_hop = $rout_tbl[next_node][0]
              else
                rout_cond = $rout_tbl.has_key?(dst)
                next_hop = $rout_tbl[dst][0] 
              end
              if rout_cond
                to_send = "MSG" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
                
              else
                send_fail_packet(packet)
              end
            end
          end
        elsif line.include? "CIRCUITB"
          line.chomp!
          arr = line.split("\t")
          packet = Packet.new
          packet.from_json! arr.last
          #puts packet.to_json
          dst = packet.header["dst"]
          src = packet.header["src"]
          id = packet.header["circ_id"]
          path = packet.header["circ_path"]
          current_hop = packet.header["next_hop"]
          if path[0] == $hostname
            if src == path.last && packet.header["circ_success"] == true
              STDOUT.puts "CIRCUITB #{id} --> #{path.last} over #{path.length-2}"
            
            elsif packet.header["circ_success"] == false
              STDOUT.puts "CIRCUIT ERROR: #{$hostname} -/-> #{path.last} FAILED AT #{packet.header["circ_fail"]}"
            end
          elsif dst == $hostname
            if !$circuit_member.include?(id)
              $circuit_member.push(id)
              $circuits[id] = path
              if $rout_tbl.has_key?(src)
                next_hop = $rout_tbl[src][0]
                packet.header["dst"] = src
                packet.header["src"] = $hostname
                packet.header["circ_success"] = true
                packet.header["circ_response"] = true 
                to_send = "CIRCUITB" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
              end
              STDOUT.puts "CIRCUIT #{src}/#{id} --> #{$hostname} over #{path.length-2}"
            else

              
            end

            
          elsif packet.header["circ_response"] == true
            if $rout_tbl.has_key?(dst)
                next_hop = $rout_tbl[dst][0]
                to_send = "CIRCUITB" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
              end
           
          else
            
            next_node = path[path.index(current_hop) + 1]
            puts next_node
            if !$circuit_member.include?(id)
              $circuit_member.push(id)
              $circuits[id] = path
              if $rout_tbl.has_key?(next_node)
                next_hop = $rout_tbl[next_node][0]
                packet.header["next_hop"] = next_node
                to_send = "CIRCUITB" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
              else
                if $rout_tbl.has_key?(src)
                  next_hop = $rout_tbl[src][0]
                  packet.header["dst"] = src
                  packet.header["src"] = $hostname
                  packet.header["circ_success"] = false
                  packet.header["circ_response"] = true
                  packet.header["circ_fail"] = next_node
                  to_send = "CIRCUITB" + "\t" + "#{packet.to_json}" + "\n"
                  $connections[next_hop].puts to_send
                end
              end
              
             # if $rout_tbl.has_key?(src)
             #   next_hop = $rout_tbl[src][0].name
             #   packet.header["dst"] = src
             #   packet.header["src"] = $hostname
             #   packet.header["circ_success"] = true
             #   packet.header["circ_response"] = true           
             #   to_send = "CIRCUITB" + "\t" + "#{packet.to_json}" + "\n"
              #  $connections[next_hop].puts to_send
             # end
            else
              if $rout_tbl.has_key?(src)
                next_hop = $rout_tbl[src][0]
                packet.header["dst"] = src
                packet.header["src"] = $hostname
                packet.header["circ_response"] = true
                packet.header["circ_success"] = false
                to_send = "CIRCUITB" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
              end
              
              
            end
          end
        elsif line.include? "CIRCUITD"
          line.chomp!
          arr = line.split("\t")
          packet = Packet.new
          packet.from_json! arr.last
          puts packet.to_json
          dst = packet.header["dst"]
          src = packet.header["src"]
          id = packet.header["circ_id"]
          path = packet.header["circ_path"]
          current_hop = packet.header["next_hop"]
          circ_success = packet.header["circ_success"]
          if path[0] == $hostname
            if src == path.last && circ_success == true
              STDOUT.puts "CIRCUITD #{id} --> #{src} over #{path.length-2}"
              $circuits.delete(id)
              $circuit_member.delete(id)
            elsif packet.header["circ_success"] == false
              STDOUT.puts "CIRCUIT ERROR: #{$hostname} -/-> #{path.last} FAILED AT #{packet.header["circ_fail"]}"
            end

          elsif dst == $hostname
            if $circuit_member.include?(id)
              $circuits.delete(id)
              $circuit_member.delete(id)
              if $rout_tbl.has_key?(src)
                next_hop = $rout_tbl[src][0]
                packet.header["dst"] = src
                packet.header["src"] = $hostname
                packet.header["circ_success"] = true
                packet.header["circ_response"] = true 
                to_send = "CIRCUITD" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
              end

          end
          elsif packet.header["circ_response"] == true
            if $rout_tbl.has_key?(dst)
              next_hop = $rout_tbl[dst][0]
              to_send = "CIRCUITD" + "\t" + "#{packet.to_json}" + "\n"
              $connections[next_hop].puts to_send
            end
          else
            next_node = path[path.index($hostname) + 1]
            if $circuit_member.include?(id)
              $circuit_member.delete(id)
              $circuits.delete(id)
              if $rout_tbl.has_key?(next_node)
                next_hop = $rout_tbl[next_node][0]
                packet.header["next_hop"] = next_node
                to_send = "CIRCUITD" + "\t" + "#{packet.to_json}" + "\n"
                $connections[next_hop].puts to_send
              else
                if $rout_tbl.has_key?(src)
                  next_hop = $rout_tbl[src][0]
                  packet.header["dst"] = src
                  packet.header["src"] = $hostname
                  packet.header["circ_success"] = false
                  packet.header["circ_response"] = true
                  packet.header["circ_fail"] = next_node
                  to_send = "CIRCUITD" + "\t" + "#{packet.to_json}" + "\n"
                  $connections[next_hop].puts to_send
                end
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
      $local_nodes[cmd[2]] = Node.new(cmd[2])
      $topography.add_node($local_nodes[cmd[2]])
      $topography.add_edge($local_nodes[$hostname],$local_nodes[cmd[2]],1)
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
      $queue.push("LEDGE " + cmd.join(" "))
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
  ###### $rout_tbl['sender'][2] = seq_number
  # $mutex.synchronize do
  $seq_number[sender] = seq_number
  
  # add sender to $local_nodes if not present
  $mutex.synchronize do
    unless $local_nodes.has_key?(sender)
      $local_nodes[sender] = Node.new(sender)
      $topography.add_node($local_nodes[sender])
    end
  end
  # update topography
  link_state_hash.each do |key,value|
    $mutex.synchronize do
      unless $local_nodes.has_key?(key)
        $local_nodes[key] = Node.new(key)
      end
    end
    $mutex.synchronize do
      unless $topography.has_node?($local_nodes[key])
        $topography.add_node($local_nodes[key])
      end
      $topography.add_edge($local_nodes[sender],$local_nodes[key],value[1])
    end
  end
  #Remove any edges that have been removed from the network from the local topography
  edges_l = $topography.get_edges_from_node($local_nodes[sender])
  edges_r = []
  link_state_hash.each do |key,value|
    edges_r.push(Edge.new($local_nodes[sender],$local_nodes[key],0))
    edges_r.push(Edge.new($local_nodes[key],$local_nodes[sender],0))
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
  run_dijkstras
  
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
 # fd = File.open($hostname + "test", "a")
  
    #puts $topography.edges
    
    #  fd.puts "_________________________________"
    #  fd.puts $topography.edges
    #  fd.puts $rout_tbl
    #  fd.puts $local_nodes[$hostname]
    #fd.puts $local_nodes.keys
    #fd.puts $local_nodes.values
  $mutex.synchronize do
    $dijkstra = Dijkstra.new($topography, $local_nodes[$hostname])
  end
    #  fd.puts "Djikstra done\n"  
  
  
  $mutex.synchronize do
    
    $local_nodes.each do |name, value|
      if name != $hostname && $dijkstra != nil
        if $topography.reachable?(value, $local_nodes[$hostname])
          #  puts "Dijkstra edges: #{$dijkstra.graph.edges}"
          #  puts "Dijkstra source node: #{$dijkstra.source_node}"
          #  puts "Dijkstra path: #{$dijkstra.path_to}"
          #  puts "Dijkstra distance: #{$dijkstra.distance_to}"
          #  puts "Local nodes: #{$local_nodes}"
          #  puts "Routing Table: #{$rout_tbl}"
          path = $dijkstra.shortest_path_to(value)
          if path != nil && path.length > 0
            $rout_tbl[name] = [path[1].name,$dijkstra.distance_to[value]]
            #  puts "YES3"
          end
        end
      end
    end
    
    end
#  fd.close
  #end
  
end

# Send link state update to all neighbors
def send_link_state()
  #puts "sending link state"
 # begin
    run_dijkstras
 # rescue => exception
 #   puts exception.backtrace
 #   raise
 #end
 # puts "made it"
  #create and populate hash of neighbors to send with link state message
  #puts "dijkstras"
  neighbors = Hash.new()
  $connections.each do |key,connection|
    #first and second element of array into neighbors hash
    
    $mutex.synchronize do
      if $rout_tbl.has_key?(key)
        neighbors[key] = $rout_tbl[key]
      end
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
  puts "DELETE"
  $topography.remove_edge($local_nodes[$hostname],$local_nodes[cmd[0]])
  $local_nodes.delete(cmd[0])
  $rout_tbl.delete(cmd[0])
  puts $rout_tbl
  $connections.delete(cmd[0])
  send_link_state
  
	#STDOUT.puts "EDGED: not implemented"
end

def edgeu(cmd)
  $topography.add_edge($local_nodes[$hostname],$local_nodes[cmd[0]],cmd[1].to_i)
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
  if packet.header["circ_path"] != nil
    path = packet.header["circ_path"]
    next_node = path[path.index($hostname)-1]
    rout_cond = $rout_tbl.has_key?(next_node)
    next_hop = $rout_tbl[next_node][0]
  else
    rout_cond = $rout_tbl.has_key?(packet.header["src"])
    next_hop = $rout_tbl[packet.header["src"]][0]
  end
  if rout_cond
    to_send = "MSG" + "\t" + "#{fail_packet.to_json}" + "\n"
    $connections[next_hop].puts to_send
  end
end

def send_fail_ftp_packet(packet)
  STDOUT.puts "FTP ERROR: #{packet.header["src"]} −− > #{packet.header["ftp_path"]}/#{packet.header["ftp_name"]}"
  # fail_packet = Packet.new
  packet.header["dst"] = packet.header["src"]
  packet.header["src"] = $hostname
  src = packet.header["src"]
  # fail_packet.header["fail"] = true
  # fail_packet.header["ftp"] = true
  packet.header["fail"] = true
  if packet.header["circ_path"] != nil
    path = packet.header["circ_path"]
    next_node = path[path.index($hostname)-1]
    rout_cond = $rout_tbl.has_key?(next_node)
    next_hop = $rout_tbl[next_node][0]
  else
    rout_cond = $rout_tbl.has_key?(src)
    next_hop = $rout_tbl[src][0]
  end
  if rout_cond
    to_send = "MSG" + "\t" + "#{packet.to_json}" + "\n"
    $connections[next_hop].puts to_send
  end
end


def sendmsg(cmd, *circm)
  
    
  #STDOUT.puts "SENDMSG: not implemented"
  #cmd[0] = DST
  #cmd[1] = MSG
  err_flag = false
  payload = cmd[1]
  payload_len = payload.bytesize
  tracker = 0
  offset = 0
  #TODO check if err_flag logic is correct
  while payload_len > $maxPayload || err_flag == true
    msg_packet = Packet.new
    if circm.any?
      path = $circuits[circm[0].to_s]
      rout_cond = $rout_tbl.has_key?(path[1])
      next_hop = $rout_tbl[path[1]][0]
      msg_packet.header["circ_path"] = path
    else
      rout_cond = $rout_tbl.has_key?(cmd[0])
      next_hop = $rout_tbl[cmd[0]][0]
    end

    if rout_cond
      
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
      to_send = "MSG" + "\t" + "#{msg_packet.to_json}" + "\n"
      $connections[next_hop].puts to_send
    else
      STDOUT.puts "SENDMSG ERROR: HOST UNREACHABLE"
      err_flag = true
    end
  end
  if payload_len > 0
    if circm.any?
      path = $circuits[circm[0].to_s]
      rout_cond = $rout_tbl.has_key?(path[1])
      next_hop = $rout_tbl[path[1]][0]
      msg_packet.header["circ_path"] = path
    else
      rout_cond = $rout_tbl.has_key?(cmd[0])
      next_hop = $rout_tbl[cmd[0]][0]
    end
    if rout_cond
      msg_packet = Packet.new
      msg_packet.header["dst"] = cmd[0] #sets dst header field
      msg_packet.header["src"] = $hostname
      msg_packet.header["len"] = payload_len #sets length header field
      msg_packet.header["ID"] = $ID_counter
      msg_packet.header["offset"] = offset + payload_len
      msg_packet.header["mf"] = false
      msg_packet.msg = payload[tracker..payload.bytesize]
      to_send = "MSG" + "\t" + "#{msg_packet.to_json}" + "\n"
      $connections[next_hop].puts to_send
    end
  end
  $ID_counter = $ID_counter + 1
end

def check_ping_timeout(seq_id)
  Thread.new do
    sleep $pingTimeout
    $mutex.synchronize do
      if $ping_responses[seq_id] == 0
        STDOUT.puts "PING ERROR: HOST UNREACHABLE" 
      end
    end
  end
end

def ping(cmd, *circm)
  #STDOUT.puts "PING: not implemented"
  #cmd[0] = DST
  #cmd[1] = NUMPINGS
  #cmd[2] = DELAY (between pings)
  dst = cmd[0]
  pings = cmd[1].to_i
  delay = cmd[2].to_i
  seq_id = 0
  ping_packet = Packet.new
  if circm.any?
    path = $circuits[circm[0].to_s]
    rout_cond = $rout_tbl.has_key?(path[1])
    next_hop = $rout_tbl[path[1]][0]
    ping_packet.header["circ_path"] = path
  else
    rout_cond = $rout_tbl.has_key?(dst)
    next_hop = $rout_tbl[dst][0]
  end
  ping_packet.header["dst"] = dst
  ping_packet.header["src"] = $hostname
  ping_packet.header["ping"] = true
  ping_packet.header["ping_src"] = $hostname
  ping_packet.header["seq_num"] = seq_id
  while pings > 0
    $ping_responses[seq_id] = 0
    if rout_cond
      ping_packet.header["sent_time"] = Time.now
      ping_packet.header["seq_num"] = seq_id
      to_send = "MSG" + "\t" + "#{ping_packet.to_json}" + "\n"
      $connections[next_hop].puts to_send
      check_ping_timeout(seq_id)
    else
      STDOUT.puts "PING ERROR: HOST UNREACHABLE"
    end
    pings = pings - 1
    seq_id = seq_id + 1
    sleep delay
  end

end

def flush_trace_buffer(trace_num)
  Thread.new do
    printed = false
    now = Time.now
    while true && !printed && Time.now - now <= 5
      $mutex.synchronize do
        if $trace_buffer.length == trace_num
          $trace_buffer.each do |key,value|
            STDOUT.puts value
          end
          $trace_buffer.clear
          printed = true
        end
      end  
    end
    if printed == false
      $mutex.synchronize do
        counter = 0
        while counter < $trace_buffer.length
          STDOUT.puts $trace_buffer[counter]
          counter = counter + 1
        end
        $trace_buffer.clear
      end
    end
  end
end

def check_trace_timeout(hop_count)
  Thread.new do
    sleep $pingTimeout
    $mutex.synchronize do
      if $trace_responses[hop_count] == 0
        if !$trace_buffer.has_key?(hop_count)
          $trace_buffer[hop_count] = "TIMEOUT on #{hop_count}"
        end
      end
    end
  end
end


def traceroute(cmd, *circm)
  # STDOUT.puts "TRACEROUTE: not implemented"
  # cmd[0] = dst
  
  dst = cmd[0]
  path_len = $dijkstra.shortest_path_to($local_nodes[dst]).length
  hop_count = 0
  trace_packet = Packet.new
  if circm.any?
    path = $circuits[circm[0].to_s]
    rout_cond = $rout_tbl.has_key?(path[1])
    next_hop = $rout_tbl[path[1]][0]
    trace_packet.header["circ_path"] = path
  else
    rout_cond = $rout_tbl.has_key?(dst)
    next_hop = $rout_tbl[dst][0]
  end
  trace_packet.header["dst"] = dst
  trace_packet.header["src"] = $hostname
  trace_packet.header["seq_num"] = 1
  trace_packet.header["ping_src"] = $hostname
  trace_packet.header["trace"] = true
  trace_packet.header["sent_time"] = Time.now
  trace_packet.header["path_length"] = path_len
  if rout_cond
    to_send = "MSG" + "\t" + "#{trace_packet.to_json}" + "\n"
    $connections[next_hop].puts to_send
    $trace_buffer[hop_count] = "0 " + "#{$hostname}" + " 0"
    hop_count = hop_count + 1
    counter = 1
    while counter < path_len
      $trace_responses[counter] = 0
      counter = counter + 1
    end
    while hop_count < path_len
      check_trace_timeout(hop_count)
      hop_count = hop_count + 1
    end
    flush_trace_buffer(path_len)

  else
    STDOUT.puts "ERROR: No path"
  end
end

def ftp(cmd, *circm)
    
  #STDOUT.puts "SENDMSG: not implemented"
  #cmd[0] = DST
  #cmd[1] = MSG
  # Open file
  file = File.open(cmd[1])
    err_flag = false
    #payload = cmd[1]
    payload_len = file.size
    tracker = 0
    offset = 0
    count = 0
    until file.eof? || err_flag == true
      if circm.any?
        path = $circuits[circm[0].to_s]
        rout_cond = $rout_tbl.has_key?(path[1])
        next_hop = $rout_tbl[path[1]][0]
        ping_packet.header["circ_path"] = path
      else
        rout_cond = $rout_tbl.has_key?(cmd[0])
        next_hop = $rout_tbl[cmd[0]][0]
      end
      if rout_cond
        count += 1
        payload = file.read($maxPayload)
        msg_packet = Packet.new
        msg_packet.header["dst"] = cmd[0] #sets dst header field
        msg_packet.header["src"] = $hostname
        msg_packet.header["ID"] = $ID_counter
        msg_packet.header["offset"] = offset

        #Figure out if at end of the file or not.
        mf = true
        if payload_len % $maxPayload != 0
          mf = (payload.bytesize == $maxPayload)
        elsif count == payload_len / $maxPayload
          mf = false
        end
        msg_packet.header["len"] = payload.bytesize
        msg_packet.header["mf"] = mf
        msg_packet.header["ftp"] = true
        msg_packet.header["ftp_path"] = cmd[2]
        msg_packet.header["ftp_name"] = cmd[1]
        msg_packet.msg = payload
        offset = offset + payload.bytesize
        to_send = "MSG" + "\t" + "#{msg_packet.to_json}" + "\n"
        $connections[next_hop].puts to_send

      else
        STDOUT.puts "SENDMSG ERROR: HOST UNREACHABLE"
        err_flag = true
      end
    end
  if err_flag == true

  end
  file.close
  # if payload_len > 0
  #   msg_packet = Packet.new
  #   msg_packet.header["dst"] = cmd[0] #sets dst header field
  #   msg_packet.header["src"] = $hostname
  #   msg_packet.header["len"] = payload_len #sets length header field
  #   msg_packet.header["ID"] = $ID_counter
  #   msg_packet.header["offset"] = offset + payload_len
  #   msg_packet.header["mf"] = false
  #   msg_packet.msg = payload[tracker..payload.bytesize]
  #   next_hop = $rout_tbl[cmd[0]][0].name #next_hop router name
  #   to_send = "MSG" + "\t" + "#{msg_packet.to_json}" + "\n"
  #   $connections[next_hop].puts to_send
  # end
  $ID_counter = $ID_counter + 1
  
end

def circuitb(cmd)
  #STDOUT.puts "CIRCUITB not implemented"
  # cmd[0] = CIRCUITID
  # cmd[1] = dst
  # cmd[2] = CIRCUIT (list of nodes)
  if $circuits[cmd[0]].include? $hostname
    STDOUT.puts "CIRCUIT ERROR: THIS NODE IS ALREADY PART OF A CIRCUIT WITH THIS ID"
  else
    if cmd[2] == nil
      path = []
    else
      path = cmd[2].split(",")
    end  
    path.unshift($hostname)
    path.push(cmd[1])
    $circuits[cmd[0]] = path
    $circuit_member.push(cmd[0])
    circuitb_packet = Packet.new
    circuitb_packet.header["dst"] = cmd[1]
    circuitb_packet.header["src"] = $hostname
    circuitb_packet.header["circ_path"] = path
    circuitb_packet.header["next_hop"] = path[1]
    circuitb_packet.header["circ_id"] = cmd[0]
    if $rout_tbl.has_key?(path[1])
      next_hop = $rout_tbl[path[1]][0]
      to_send = "CIRCUITB" + "\t" + "#{circuitb_packet.to_json}" + "\n"
      $connections[next_hop].puts to_send
    else
      STDOUT.puts "CIRCUIT ERROR: #{$hostname} -/-> #{cmd[1]} at #{path[1]}"
    end
  end
end

def circuitm(cmd)
  #STDOUT.puts "CIRCUITM not implemented"
  #cmd[0] = CIRCUITID
  #cmd[1] = MSG(SENDMSG, PING, etc.)
  if $circuits[cmd[0]][0] != $hostname
      STDOUT.puts "CIRCUIT ERROR: THIS NODE IS NOT THE START OF THE CIRCUIT"
  else
    cmd_send = []
    if cmd[1] == "SENDMSG"
      cmd_send.push(cmd[2])
      cmd_send.push(cmd[3])
      sendmsg(cmd_send,cmd[0])
    elsif cmd[1] == "PING"
      cmd_send.push(cmd[2])
      cmd_send.push(cmd[3])
      cmd_send.push(cmd[4])
      ping(cmd_send,cmd[0])
    elsif cmd[1] == "TRACEROUTE"
      cmd_send.push(cmd[2])
      traceroute(cmd_send,cmd[0])
    elsif cmd[1] == "FTP"
      cmd_send.push(cmd[2])
      cmd_send.push(cmd[3])
      cmd_send.push(cmd[4])
      ftp(cmd_send,cmd[0])
    else
      STDOUT.puts "INVALID MSG TYPE"
    end
  end
end

def circuitd(cmd)
  #STDOUT.puts "CIRCUITD not implemented"
  #cmd[0] = CIRCUITID
  if $circuits[cmd[0]][0] != $hostname
    STDOUT.puts "CIRCUIT ERROR: THIS NODE IS NOT THE START OF THE CIRCUIT"
  else
    path = $circuits[cmd[0]]
    circuitd_packet = Packet.new
    circuitd_packet.header["dst"] = path.last
    circuitd_packet.header["src"] = $hostname
    circuitd_packet.header["circ_path"] = path
    circuitd_packet.header["next_hop"] = path[1]
    circuitd_packet.header["circ_id"] = cmd[0]
    if $rout_tbl.has_key?(path[1])
      next_hop = $rout_tbl[path[1]][0]
      to_send = "CIRCUITD" + "\t" + "#{circuitd_packet.to_json}" + "\n"
      $connections[next_hop].puts to_send
    else
      STDOUT.puts "CIRCUIT ERROR: #{$hostname} -/-> #{cmd[1]} at #{path[1]}"
    end
  end
end


# do main loop here....
def main()
  while(line = STDIN.gets())
    if line.include? "check"
      puts $rout_tbl
    end
    if line.include? "ftp2"
      line = "FTP n2 test_ftp /mnt/hgfs/p3/dest\n"
      line = line.strip()
      arr = line.split(' ')
      cmd = arr[0]
      args = arr[1..-1]
      ftp(args)
    end
    if line.include? "ftp3"
      line = "FTP n3 test_ftp /mnt/hgfs/p3/dest\n"
      line = line.strip()
      arr = line.split(' ')
      cmd = arr[0]
      args = arr[1..-1]
      ftp(args)
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
        when "CIRCUITB"; circuitb(args)
        when "CIRCUITM"; circuitm(args)
        when "CIRCUITD"; circuitd(args)
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
  $local_nodes[$hostname] = Node.new($hostname)
  $topography.add_node($local_nodes[$hostname])
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





