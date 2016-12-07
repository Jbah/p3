require_relative 'jsonable'

class Packet < JSONable
  attr_accessor :header
  attr_accessor :msg

  def initialize
    @header = {"dst" => nil, "src" => nil, "ID"=>nil,
      "len" => 0, "offset" => 0, "mf" => false, "trace"=>false,
    "hop_count" => 0,"ping" => false, "fail" => false, "sent_time" => 0,
    "ping_src"=>nil, "seq_num"=>0, "trace" => false, "ftp"=>false, "ftp_path"=>nil, "ftp_name"=>nil}
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
