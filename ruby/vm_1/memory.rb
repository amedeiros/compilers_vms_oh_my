class Memory < Hash
  attr_reader :outer

  def initialize(outer=nil)
    super()
    @outer = outer
  end

  def [](key)
    return super(key) if key?(key)
    val = nil
    val = @outer[key] unless @outer.nil?
    raise "MemoryError: unbound variable #{key}" if val.nil?
    val
  end
end
