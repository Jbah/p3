require_relative 'jsonable'

class Packet < JSONable
  attr_accessor :header
  attr_accessor :msg

  def initialize
    @header = {"dst" => nil, "src" => nil, "ID"=>nil,
      "len" => 0, "offset" => 0, "mf" => false, "trace"=>false,
    "hop_count" => 0,"ping" => false, "fail" => false, "sent_time" => 0,
    "ping_src"=>nil, "seq_num"=>0, "trace" => false, "trace_response" =>false,"path_length"=>0, "ftp"=>false, "ftp_path"=>nil, "ftp_name"=>nil, "circ_path"=>nil,"next_hop" => nil, "circ_success" => false,"circ_id"=>nil, "circ_fail"=>nil, "circ_response"=>false}
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
