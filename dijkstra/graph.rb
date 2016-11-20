class Graph
  attr_accessor :nodes
  attr_accessor :edges

  def initialize
    @nodes = []
    @edges = []
  end

  def add_node(node)
    nodes << node
    node.graph = self
  end

  def has_node?(node)
    return @nodes.include?(node)
  end

  #updates if contains from and to, return true if updates, false if doesnt
  def update_edge?(from, to ,weight)
    bool = false
    @edges.each() do |edge|
      if (edge.from() == from and edge.to() == to) or (edge.from() == to and edge.to() == from)
        edge.weight = weight
        bool = true
      end
    end
    return bool
  end

  def add_edge(from, to, weight)
    if not update_edge?(from, to, weight)
      edges << Edge.new(from, to, weight)
      edges << Edge.new(to,from, weight)
    end
  end
end
