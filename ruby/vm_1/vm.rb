require_relative 'memory'

class VM
  attr_reader :stack, :mem

  def initialize
    @stack = []
    @call_ip = 0
    @mem = Memory.new
  end

  def execute(*opcodes)
    ip = 0

    loop do
      code = opcodes[ip]
      case code
      when 'MUL', INSTRUCTIONS['MUL'],
           'DIV', INSTRUCTIONS['DIV'],
           'ADD', INSTRUCTIONS['ADD'],
           'SUB', INSTRUCTIONS['SUB']
        ip += 1
        arg_count = opcodes[ip]
        math(arg_count, op_code_to_math_op(code), code)
      when 'PRINT', INSTRUCTIONS['PRINT']
        puts pop_stack
      when 'PUSH', INSTRUCTIONS['PUSH'] # push int/byte
        ip += 1
        push_stack opcodes[ip]
      when 'PUSHB', INSTRUCTIONS['PUSHB'] # push bool
        ip += 1
        push_stack opcodes[ip] == 1
      when 'PUSHL', INSTRUCTIONS['PUSHL'] # push a list onto the stack
        ip += 1
        list_size_t = opcodes[ip]
        list = []
        (0..list_size_t-1).each { list << pop_stack }
        push_stack list
      when 'PUSHW', INSTRUCTIONS['PUSHW'] # push word
        # Push a word onto the stack by poping off its bytes
        # converting into string and pushing onto stack the word
        ip += 1
        len = opcodes[ip]
        bytes = []
        (0..len-1).each { bytes << pop_stack }
        push_stack bytes.pack('c*')
      when 'MOVSM', INSTRUCTIONS['MOVSM'] # Move stack -> memory
        # PUSHW the word onto the stack
        # PUSH the value onto the stack
        # MOVSM
        val = pop_stack
        word = pop_stack
        mem[word] = val
      when 'MOVMS', INSTRUCTIONS['MOVMS'] # Move memory -> stack
        # PUSHW the word on memory
        # MOVMS
        word = pop_stack
        push_stack mem[word] # TODO: "Memory" cleanup
      when 'CMP', INSTRUCTIONS['CMP'], # Equal
           'GT',  INSTRUCTIONS['GT'], # Greater than
           'LT',  INSTRUCTIONS['LT'], # Less than
           'GTE', INSTRUCTIONS['GTE'], # Greater than equal
           'LTE', INSTRUCTIONS['LTE']  # Less than equal
        ip += 1
        arg_count = opcodes[ip]
        comparison(arg_count, op_code_to_comparison(code), code)
      when 'HLT', INSTRUCTIONS['HLT']
        break
      when 'JMP', INSTRUCTIONS['JMP'] # JUMP To instruction
        ip += 1
        jmp = opcodes[ip]
        ip = jmp - 1 # jump to instruction
      when 'JMPIF', INSTRUCTIONS['JMPIF']
        result = pop_stack
        ip += 1
        body_addr = opcodes[ip]
        ip += 1
        else_addr = opcodes[ip]
        if result
          ip = body_addr - 1 # move to if body instruction
        else
          ip = else_addr - 1 # move to bytecode after if-body
        end
      when 'INT', INSTRUCTIONS['INT'] # Intterupt
        ip += 1
        exit_code = opcodes[ip]
        exit exit_code
      when 'FUNCB', INSTRUCTIONS['FUNCB'] # Func begins
        func = []
        args = []
        ip += 1
        while opcodes[ip] != INSTRUCTIONS['FUNCE']
          if opcodes[ip] == INSTRUCTIONS['ARGS']
            ip += 1
            arg_size_t = opcodes[ip]
            i = 0
            while i < arg_size_t
              args << pop_stack
              i += 1
            end
          else
            func << opcodes[ip]
          end

          ip += 1
        end
        push_stack [func, args, args.size] # push the compiled func to the stack
      when 'FUNCC', INSTRUCTIONS['FUNCC'] # Function call
        ip += 1
        arg_size_t = opcodes[ip]
        func_name = pop_stack
        func = mem[func_name]
        raise "Missing or added parameters to function #{func_name}" if func[2] != arg_size_t
        scoped_mem = Memory.new(@mem)
        func[1].each { |x| scoped_mem[x] = pop_stack } # load args
        @mem = scoped_mem # memory scope change
        execute(*func[0]) # execute the function
        @mem = scoped_mem.outer # memory scope change back
      when 'RBFC', INSTRUCTIONS['RBFC'] # call a ruby method on the object on the stack
        ip += 1
        arg_size_t = opcodes[ip]
        args = []
        (0..arg_size_t-1).each { args.push pop_stack }
        obj = pop_stack
        meth = pop_stack
        push_stack obj.send(meth, *args)
      when 'RBCC', INSTRUCTIONS['RBCC'] # call a ruby method on class passing params
        ip += 1
        arg_size_t = opcodes[ip]
        args = []
        (0..arg_size_t-1).each { args.push pop_stack }
        klass = pop_stack.constantize
        meth = pop_stack
        push_stack klass.send(meth, *args)
      else
        raise "Unkown opcode: #{code}"
      end

      # Move to the next opcode
      ip += 1
      break if ip >= opcodes.size
      # raise 'Unexpected end of file' if ip >= opcodes.size
    end

    nil
  end

  private

  def pop_stack
    stack.pop
  end

  def push_stack(v)
    stack.push v
  end

  def opcode_or_exception(ops, ip, msg)
    v = ops[ip]
    raise msg if v.nil?
    v
  end

  def math(arg_size_t, operation, code)
    arg1 = pop_stack
    (0..arg_size_t-2).each do
      arg1 = arg1.send(operation, pop_stack)
    end

    push_stack arg1
  end

  def comparison(arg_size_t, operation, code)
    arg1 = pop_stack
    result = true
    (0..arg_size_t-2).each do
      if result == false
        pop_stack # clear the stack operands
      else
        r = pop_stack
        result = arg1.send(operation, r)
        arg1 = r
      end
    end

    push_stack result
  end

  def op_code_to_comparison(opcode)
    case opcode
    when INSTRUCTIONS['CMP'], 'CMP'  then :==
    when INSTRUCTIONS['GT'],  'GT'  then :>
    when INSTRUCTIONS['LT'],  'LT'  then :<
    when INSTRUCTIONS['GTE'], 'GTE' then :>=
    when INSTRUCTIONS['LTE'], 'LTE' then :<=
    else
      raise "Unknown opcode #{opcode} for comparison operator"
    end
  end

  def op_code_to_math_op(opcode)
    case opcode
    when INSTRUCTIONS['MUL'], 'MUL' then :*
    when INSTRUCTIONS['DIV'], 'DIV' then :/
    when INSTRUCTIONS['ADD'], 'ADD' then :+
    when INSTRUCTIONS['SUB'], 'SUB' then :-
    else
      raise "Unknown opcode #{opcode} for math operator"
    end
  end
end

# # Write code to file.
# # q | Integer | 64-bit signed, native endian (int64_t)
# File.open('test.bin', 'wb') { |file| file.write(c.bytecode.pack("q*")) }

# # Read from file and execute
# # q | Integer | 64-bit signed, native endian (int64_t)
# vm.execute *File.read('test.bin').unpack("q*")
