class Node
  attr_accessor :name, :graph :test

  def initialize(name)
    @name = name
  end


  def == (other_node)
    return self.name == other_node.name
  end

  def adjacent_edges
    graph.edges.select{|e| e.from == self}
  end

  def to_s
    @name
  end
end
