require_relative 'dijkstra/dijkstra'
require_relative 'dijkstra/node'
require_relative 'dijkstra/edge'
require_relative 'dijkstra/graph'
require 'pp'

graph = Graph.new

graph.add_node(n1=Node.new("n1"))
graph.add_node(n2=Node.new("n2"))
graph.add_node(n3=Node.new("n3"))
graph.add_node(n4=Node.new("n4"))

# graph.add_edge(n1,n4,10)
# graph.add_edge(n1,n3,2)
# graph.add_edge(n1,n2,1)
# graph.add_edge(n2,n4,2)
# graph.add_edge(n3,n4,3)
graph.add_edge(n1,n2,4)
graph.add_edge(n1,n2,5)
d = Dijkstra.new(graph, n1)
puts graph.edges
for elt in graph.edges
  puts elt.to_s
end

puts graph.has_node?(n1)
puts graph.get_weight(n1,n2)
#print graph.edges[0].to_s
#print 'hello'
shortest_path = d.shortest_path_to(n2)
puts shortest_path
#pp d.distance_to()[n1]
# for elt in shortest_path
#   print elt.name
#   print "\n"
# end
#pp shortest_path.map(&:to_s)