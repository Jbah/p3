class Edge
  attr_accessor :from, :to, :weight

  def initialize(from, to, weight)
    @from, @to, @weight = from, to, weight
  end

  def from()
    return @from
  end

  def to()
    return @to
  end

  def weight()
    return @weight
  end

  def == (other_edge)
    if ((other_edge.to == to) and (other_edge.from == from)) or ((other_edge.to == from) and (other_edge.from == to))
      return true
    else
      return false
    end
  end

  def <=>(other)
    self.weight <=> other.weight
  end

  def to_s
    "#{from.to_s} => #{to.to_s} with weight #{weight}"
  end
end
