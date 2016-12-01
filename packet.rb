require_relative 'jsonable'

class Packet < JSONable
  attr_accessor :header
  attr_accessor :msg

  def initialize
    @header = {"dst" => nil, "src" => nil, "ID"=>nil,
      "len" => 0, "offset" => 0, "mf" => false}
    @msg = ""
  end

  def get_size
    len = 0
    @header.each do |key|
      len = len +  key.length
    end
    len = len + msg.length
    return len
  end

end
