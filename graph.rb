class Graph
  attr_accessor :nodes
  attr_accessor :edges

  def initialize
    @nodes = []
    @edges = []
  end

  def add_node(node)
    @nodes << node
    node.graph = self
  end

  def has_node?(node)
    return @nodes.include?(node)
  end
  def get_adjacent_nodes(node)
    ret = []
    for edge in @edges
      if edge.from == node
        ret.push(edge.to)
      end
    end
    return ret
  end

  def reachable?(node1,node2)
    found = []
    to_traverse = []
    found.push(node2)
    to_traverse.push(node2)
    i = 0
    next_node = node2
    while !to_traverse.empty? || i == 100
      to_visit = get_adjacent_nodes(next_node)
      to_visit.each do |ele|
        if !found.include?(ele)
          to_traverse.push(ele)
        end
      end      
      to_traverse.each do |ele|
        if !found.include?(ele)
          found.push(ele)
        end
      end
      next_node = to_traverse.pop
      i = i + 1
    end
    if found.include?(node1)
      return true
    else
      return false
    end
  end
  def get_weight(from,to)
    for edge in @edges
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
    for edge in @edges
      if edge.to == node or edge.from == node
        ret.push(edge)
      end
    end
    return ret
  end

  def add_edge(from, to, weight)
    if not update_edge?(from, to, weight)
      @edges << Edge.new(from, to, weight)
      @edges << Edge.new(to,from, weight)
    end
  end

  def remove_edge(from,to)
    to_delete = []
    for edge in @edges
      if (edge.from == from and edge.to == to) or (edge.from == to and edge.to == from)
        to_delete.push(edge)
      end
    end
    for elt in to_delete
      @edges.delete(elt)
    end
  end
end
