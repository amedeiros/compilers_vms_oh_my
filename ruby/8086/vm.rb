# References
# http://datasheets.chipdb.org/Intel/x86/808x/datashts/8086/231455-006.pdf
# https://github.com/NeatMonster/Intel8086/blob/master/src/fr/neatmonster/ibmpc/Intel8086.java#L1039
# https://www.ic.unicamp.br/~celio/mc404/opcodes.html
# https://en.wikipedia.org/wiki/X86_instruction_listings

# The 8086 has two processing units.
# The Bus Interface Unit (BUI) and Execution Unit (EU).
# Both can interact and act independently of one another.
# BUI handles instruction fection and queueing, operand fetching and store
# and address relocation.
require 'byebug'

class Object
  def attr_accessor_with_default(sym, default)
    attr_reader_with_default(sym, default)
    self.class_eval("def #{sym}=(val); @#{sym}=val; end")
  end

  def attr_reader_with_default(sym, default)
    self.class_eval("def #{sym}; @#{sym} || #{default}; end")
  end
end

class VM
  # - Segments -
  #
  # Memory is addressed as 00000(H) to FFFFF(H).
  # Memory is logically divided into
  # code, data, extra data and stack segments of up to 64K bytes each.
  # Segments are on 16-bit boundaries.

  # CS - Code Segment
  # Memory Reference - Instructions
  # Automatic with all instruction prefetch.
  # Points to the current code segment.
  attr_accessor_with_default :cs, 0

  # SS - Stack Segment
  # Memory Reference - Stack
  # All stack pushes and pops. Memory references relative to BP
  # base register except data references.
  attr_accessor_with_default :ss, 0

  # DS - Data Segment
  # Memory Reference - Local Data
  # Data references when relative to stack, destination of string
  # operation, or explicity overidden.
  # Contains program variables generally.
  attr_accessor_with_default :ds, 0

  # ES - Extra Segment
  # Memory Reference - External Global Data
  # Destination of string operations: explicitly selected using
  # a segment override.
  attr_accessor_with_default :es, 0

  # OS - Overidden Segment
  # Contains the overidden segment
  attr_accessor_with_default :os, 0

  # - Memory -
  # The 8086 can accommodate up to 1,048,576 bytes of memory in both minimum and maximum mode.
  #
  attr_accessor :memory

  # - Pointers / Indexs -

  # SP - Stack Pointer
  attr_accessor_with_default :sp, 0

  # BP - Base Pointer
  attr_accessor_with_default :bp, 0

  # SI - Source Index
  attr_accessor_with_default :si, 0

  # DI - Destination Index
  attr_accessor_with_default :di, 0

  # IP - Instruction Pointer
  attr_accessor_with_default :ip, 0

  # - Registers -

  # AX - Accumulator
  attr_accessor_with_default :ah, 0
  attr_accessor_with_default :al, 0
  # AX - Operand Code
  AX = 0b000

  # CX - Count
  attr_accessor_with_default :ch, 0
  attr_accessor_with_default :cl, 0
  # CX - Operand Code
  CX = 0b001

  # DX - Data
  attr_accessor_with_default :dh, 0
  attr_accessor_with_default :dl, 0
  # DX - Operand Code
  DX = 0b010

  # BX - Base
  attr_accessor_with_default :bh, 0
  attr_accessor_with_default :bl, 0
  # BX - Operand Code
  BX = 0b011

  # Queue
  # The BUI loads instructions into the queue.
  # The queue can hold up to 6 instructions bytes.
  # The queue is treated as FIFO.
  attr_accessor :queue

  # Instruction operations
  # Operates on byte data
  B = 0b0
  # Operates on word data
  W = 0b1

  # - Flags -
  # Flags are each on bit and are a 16-bit object.
  # We shift each 1 bit by the bits it fits into the 16-bit
  # FLAGS e X:X:X:X:(OF):(DF):(IF):(TF):(SF):(ZF):X:(AF):X:(PF):X:(CF)
  # CF 1 < 0, PF 1 < 2 .. OF 1 < 11

  # Flag - EU posts the flag here
  attr_accessor :flags

  # CF - Carry Flag
  CF = 1 << 0
  # PF - Parity Flag
  PF = 1 << 2
  # AF - Auxiliary Carry Flag
  AF = 1 << 4
  # ZF - Zero Flag
  ZF = 1 << 6
  # SF - Sign Flag
  SF = 1 << 7
  # TF - Trap Flag
  TF = 1 << 8
  # IF - Interrupt Flag
  IF = 1 << 9
  # DF - Direction Flag
  DF = 1 << 10
  # OF - Overflow Flag
  OF = 1 << 11

  # Clock cycles
  attr_accessor :clocks

  # Lookup table for masks/clipping results
  MASK = [0xff, 0xffff]
  # Loopup table for setting sign and overflow flags
  BITS = [8, 16]

  def initialize
    reset
  end

  # Loads a binary file into memory at a specific address
  def load(addr, path)
    f = File.open(path, "rb")
    bytes = f.read.unpack("q*")
    f.close
    self.ip = addr - 1 & 0xffff
    bytes.each_with_index do |byte, i|
      set_mem(B, get_addr(cs, ip + i), byte & 0xff)
    end

    nil
  end

  def run
    while tick; end
  end

  def to_s
    "8086 Intel"
  end

  def inspect
    "#<VM:#{self.object_id}>"
  end

  def reset
    # Flags
    self.flags = 0

    # Segments
    self.cs = 0xffff
    self.ds = 0x0000
    self.ss = 0x0000
    self.es = 0x0000

    # Queue
    self.queue = Array.new(6, 0)

    # Memory
    self.memory = Array.new(0x100000)

    # Clock
    self.clocks = 0

    nil
  end

  private

  ### MEMORY ####

  # Gets the value pointed by the instruction pointer
  # @param [Integer] w Word byte operation
  # @return [Integer] memory_value
  def get_mem(w)
    addr = get_addr(cs, ip)
    val = memory[addr]
    if w == W
      val |= memory[addr + 1] << 8
    end
    self.ip = ip + 1 + w & 0xffff
    val
  end

  # Gets the value at the specified address
  # @param [Integer] w Word byte operation
  # @return [Integer] memory_value
  def get_mem_at_addr(w, addr)
    val = memory[addr]
    if w == W
      if (addr & W) == W
        self.clocks += 4
      end
      val |= memory[addr + 1] << 8
    end

    val
  end

  # Get the absolute address from a segment and offset
  # @param [Integer] seg Segement
  # @param [Integer] offset
  # @return [Integer] address value
  def get_addr(seg, offset)
    (seg << 4) + offset
  end

  # Sets the value at the specified address
  # @param [Integer] w word/byte operation
  # @param [Integer] addr Memory address
  def set_mem(w, addr, val)
    # IBM BIOS and BASIC are ROM.
    # return if addr >= 0xf6000

    self.memory[addr] = val & 0xff
    if w == W
      if (addr & W) == W
        self.clocks += 4
      end

      self.memory[addr + 1] = val >> 8 & 0xff
    end
  end

  ### FLAGS ###

  # Get the state of a flag
  # @param [Integer] flag
  # @return [Boolean]
  def get_flag(flag)
    (flags & flag) > 0
  end

  # Sets or clears a flag
  # @param [Integer] flag The flag to affect
  # @param [Boolean] set True to set False to clean
  def set_flag(flag, set)
    if set
      self.flags |= flag
    else
      self.flags &= ~flag
    end

    nil
  end

  ### Registers ###

  # Get the value of the register/memory
  def get_rm(w, mod, rm)
    # Register to register mode
    return get_reg(w, rm) if mod == 0b11
    # Memory mode
    return get_mem(w, ea > 0 ? ea :  get_ea(mod, rm))
  end

  # Set the value of the register/memory
  def set_rm(w, mod, rm, val)
    # Register to register mode
    set_reg(w, rm, val) if mod == 0b11
    # Memory mode
    set_mem(w, ea > 0 ? ea : get_ea(mod, rm), val)
  end

  def set_reg(w, reg, val)
    if w == B
      # Byte data
      case reg
      when 0b000 # AL
        self.al = val & 0xff
      when 0b001 # CL
        self.cl = val & 0xff
      when 0b010 # DL
        self.dl = val & 0xff
      when 0b011 # BL
        self.bl = val & 0xff
      when 0b100 # AH
        self.ah = val & 0xff
      when 0b101 # CH
        self.ch = val & 0xff
      when 0b110 # DH
        self.dh = val & 0xff
      when 0b111 # BH
        self.bh = val & 0xff
      end
    else
      # Word data
      case reg
      when 0b000 # AX
        self.al = val & 0xff
        self.ah = val >> 8 & 0xff
      when 0b001 # CX
        self.cl = val & 0xff
        self.ch = val >> 8 & 0xff
      when 0b010 # DX
        self.dl = val & 0xff
        self.dh = val >> 8 & 0xff
      when 0b011 # BX
        self.bl = val & 0xff
        self.bh = val >> 8 & 0xff
      when 0b100 # SP
        self.sp = val & 0xffff
      when 0b101 # BP
        self.bp = val & 0xffff
      when 0b110 # SI
        self.si = val & 0xffff
      when 0b111 # DI
        self.di = val & 0xffff
      end
    end
  end

  # Get a register
  # @param [Integer] w byte or word register
  # @param [Integer] reg the register to return
  # @return [Integer] register
  def get_reg(w, reg)
    if w == B # Byte data
      case reg
      when 0b000 # AL
        return al
      when 0b001 # CL
        return cl
      when 0b010 # DL
        return dl
      when 0b011 # BL
        return bl
      when 0b100 # AH
        return ah
      when 0b101 # CH
        return ch
      when 0b110 # DH
        return dh
      when 0b111 # BH
        return bh
      end
    else # Word data
      case reg
      when 0b000 # AX
        return ah << 8 | al
      when 0b001 # CX
        return ch << 8 | cl
      when 0b010 # DX
        return dh << 8 | dl
      when 0b011 # BX
        return bh << 8 | bl
      when 0b100 # SP
        return sp
      when 0b101 # BP
        return bp
      when 0b110 # SI
        return si
      when 0b111 # DI
        return di
      end
    end
  end

  # Convert a unsigned value to a signed value
  # @param [Integer] w word/byte operation
  # @param [Integer] x value to convert
  def signconv(w, x)
    x << 32 - BITS[w] >> 32 - BITS[w]
  end

  ### INTERUPTS ###

  # Calls an intterupt given its type
  # @param [Integer] type
  def call_int(type)
    push(flags)
    set_flag(IF, false)
    set_flag(TF, false)
    push(cs)
    push(ip)
    byebug
    self.ip = get_mem_at_addr(W, type * 4)
    self.cs = get_mem_at_addr(W, type * 4 + 2)
  end

  # Fetches and executes an instruction
  # @return [Boolean] True if instructions remain
  def tick
    # Single step mode
    if get_flag(TF)
      call_int(1)
      self.clocks += 50
    end

    self.os = ds
    rep = 0 # Repeat
    case get_mem(B)
    when 0x26 # ES: segment override prefix
      self.os = es
      self.clocks += 2
    when 0x2e # CS: segment override prefix
      self.os = cs
      self.clocks += 2
    when 0x36 # SS: segment override prefix
      self.os = ss
      self.clocks += 2
    when 0x3e # DS: segment override prefix
      self.os = ds
      self.clocks += 2
    when 0xf2 # REPNE/REPNZ
      rep = 2
      self.clocks += 9
    when 0xf3 # REP/REPE/REPZ
      rep = 1
      self.clocks += 9
    else
      self.ip = ip - 1 & 0xffff
    end

    # Fetch instructions
    (0..5).each do |i|
      self.queue[i] = get_mem_at_addr(B, get_addr(cs, ip + i))
    end

    # Decode the first byte
    op = queue[0]
    if op.nil?
      byebug
      return false
    end
    d = op >> 1 & W
    w = op & W
    self.ip = ip + 1 & 0xffff # Increment instruction pointer

    # Only repeat a string instruction
    case op
    # 0xa4 - MOVSB Move Byte
    # 0xa5 - MOVSW Move Word
    # 0xaa - STOSB Store string data byte
    # 0xab - STOSW Strore string data word
    when 0xa4, 0xa5, 0xaa, 0xab
      self.clocks += 1 if rep.zero?
    # 0xa6 - CMPSB Compare string byte
    # 0xa7 - CMPSW Compare string word
    # 0xae - SCASB Compate byte
    # 0xaf - SCASW Compate word
    when 0xa6, 0xa7, 0xae, 0xaf
      # NO-OP
    # 0xac - LODSB Load byte
    # 0xad - LODSW Load word
    when 0xac, 0xad
      self.clocks -= 1 if rep.zero?
    else
      rep = 0
    end

    loop do
      if rep > 0
        cx = get_reg(W, CX)
        break if cx.zero? # Reached end of string
        # Decrement CX.
        set_reg(W, CX, cx - 1);
      end

      # Tick the Programmable Interval Timer.
      while clocks > 3
        self.clocks -= 4
        # pit.tick()
      end

      case op
      ## DATA TRANSFER INSTRUCTIONS
      # Register/Memory to/from Register
      # 0x88 - MOV REG8/MEM8,REG8
      # 0x89 - MOV REG16/MEM16,REG16
      # 0x8a - MOV REG8,REG8/MEM8
      # 0x8b - MOV REG16,REG16/MEM16
      case 0x88, 0x89, 0x8a, 0x8b
          decode
          if (d == 0b0) {
              src = get_reg(w, reg)
              set_rm(w, mod, rm, src)
              self.clocks += mod == 0b11 ? 2 : 9
          } else {
              src = get_rm(w, mod, rm)
              set_reg(w, reg, src)
              self.clocks += mod == 0b11 ? 2 : 8
          }
      when 0xf4 # HLT - Halt and stop
        self.clocks += 2
        return false
      when 0xe9 # JMP - Near - Direct within segment
        dst = get_mem(W)
        dst = signconv(W, dst)
        self.ip = ip + dst & 0xffff
        self.clocks += 15
      when 0xeb # JMP - Short Label - Direct within segment short
        dst = get_mem(B)
        dst = signconv(B, dst)
        self.ip = ip + dst & 0xffff
        self.clocks += 15
      when 0xea # JMP - FAR-LABEL - Direct intersegment
        dst = get_mem(W)
        src = get_mem(W)
        self.ip = dst
        self.cs = src
        self.clocks += 15
      else
        byebug
      end

      break if rep <= 0
    end

    true
  end

  # Push a value to the top of the stack
  # @param [Integer] val Value to push onto the stack
  def push(val)
    self.sp = sp - 2 & 0xffff
    set_mem(W, get_addr(ss, sp), val)
  end
end

# Load address 0xfe000
# // mov eax, imm(123) ret
# [0x48, 0xc7, 0xc0, 0xec, 0x01, 0x00, 0x00, 0xc3]
