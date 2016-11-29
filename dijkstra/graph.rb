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

  def get_weight(from,to)
    for edge in edges
      if (edge.from() == from and edge.to() == to) or (edge.from() == to and edge.to() == from)
        return edge.weight
      end
    end
    return 0
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

  def has_edge?(from,to)
    bool = false
    @edges.each() do |edge|
      if (edge.from() == from and edge.to() == to) or (edge.from() == to and edge.to() == from)
        bool = true
      end
    end
    return bool
  end

  def get_edges_from_node(node)
    ret = []
    for edge in edges
      if edge.to == node or edge.from == node
        ret.push(edge)
      end
    end
    return ret
  end

  def add_edge(from, to, weight)
    if not update_edge?(from, to, weight)
      edges << Edge.new(from, to, weight)
      edges << Edge.new(to,from, weight)
    end
  end

  def remove_edge(from,to)
    to_delete = []
    for edge in edges
      if (edge.from == from and edge.to == to) or (edge.from == to and edge.to == from)
        to_delete.push(edge)
      end
    end
    for elt in to_delete
      edges.delete(elt)
    end
  end
end
