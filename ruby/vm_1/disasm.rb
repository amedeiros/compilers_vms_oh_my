class Disasm

  def self.math(operation, args)
    arg1 = args.pop.to_i
    (0..args.size-1).each do
      r = args.pop
      break if r.nil?
      byebug if r.is_a? String
      arg1 = arg1.send(operation, r)
    end

    arg1
  end

  def self.math_op(op)
    case op
    when 'MUL', INSTRUCTIONS['MUL'] then 'MUL'
    when 'DIV', INSTRUCTIONS['DIV'] then 'DIV'
    when 'ADD', INSTRUCTIONS['ADD'] then 'ADD'
    when 'SUB', INSTRUCTIONS['SUB'] then 'SUB'
    end
  end

  def self.op_code_to_math_op(opcode)
    case opcode
    when INSTRUCTIONS['MUL'], 'MUL' then :*
    when INSTRUCTIONS['DIV'], 'DIV' then :/
    when INSTRUCTIONS['ADD'], 'ADD' then :+
    when INSTRUCTIONS['SUB'], 'SUB' then :-
    else
      raise "Unknown opcode #{opcode} for math operator"
    end
  end

  def self.comp_op(op)
    case op
    when INSTRUCTIONS['CMP'], 'CMP' then 'CMP'
    when INSTRUCTIONS['GT'],  'GT'  then 'GT'
    when INSTRUCTIONS['LT'],  'LT'  then 'LT'
    when INSTRUCTIONS['GTE'], 'GTE' then 'GTE'
    when INSTRUCTIONS['LTE'], 'LTE' then 'LTE'
    else
      raise "Unknown opcode #{op} for comparison operator"
    end
  end

  def self.op_code_to_comparison(opcode)
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

  def self.comparison(args, operation)
    arg1 = args.pop
    result = true
    (0..args.size-1).each do
      if result
        r = args.pop
        result = arg1.send(operation, r)
        arg1 = r
      end
    end

    result
  end

  def self.dis_asm(*bytecode)
    stack = []
    memory = {}
    puts "*" * 10 + " Disassmbler " + "*" * 10
    ip = 0
    while ip < bytecode.size
      op = bytecode[ip]

      case op
      when 'MUL', INSTRUCTIONS['MUL'],
           'DIV', INSTRUCTIONS['DIV'],
           'ADD', INSTRUCTIONS['ADD'],
           'SUB', INSTRUCTIONS['SUB']
        ip += 1
        args_t = bytecode[ip]
        args = []
        (0..args_t-1).each { args << stack.pop }
        puts "#{math_op(op)} #{args_t} #{args.join(" ")}"
        r = math(op_code_to_math_op(op), args)
        stack.push r
      when 'CMP',  INSTRUCTIONS['CMP'],
           'GT',  INSTRUCTIONS['GT'],
           'LT',  INSTRUCTIONS['LT'],
           'GTE', INSTRUCTIONS['GTE'],
           'LTE', INSTRUCTIONS['LTE']
        ip += 1
        args_t = bytecode[ip]
        args = []
        (0..args_t-1).each { args << stack.pop }
        puts "#{comp_op(op)} #{args_t} #{args.join(" ")}"
        r = comparison(args, op_code_to_comparison(op))
        stack.push r
      when 'PUSH', INSTRUCTIONS['PUSH']
        ip += 1
        puts "PUSH #{bytecode[ip]}"
        stack.push bytecode[ip]
      when 'PUSHW', INSTRUCTIONS['PUSHW']
        ip += 1
        args_t = bytecode[ip]
        args = []
        (0..args_t-1).each { args << stack.pop }
        stack.push args.pack('c*')
        puts "PUSHW #{args_t} #{args.join(" ")}"
      when 'MOVSM', INSTRUCTIONS['MOVSM']
        val = stack.pop
        word = stack.pop
        memory[word] = val
        puts "MOVSM #{val} #{word}"
      when 'MOVMS', INSTRUCTIONS['MOVMS']
        word = stack.pop
        stack.push memory[word]
        puts "MOVMS #{word}"
      when 'PRINT', INSTRUCTIONS['PRINT']
        puts "PRINT #{stack.pop || "STACK[0]"}"
      when 'HLT', INSTRUCTIONS['HLT']
        puts 'HLT'
        break
      when 'JMPIF', INSTRUCTIONS['JMPIF']
        result = stack.pop
        ip += 1
        body_addr = bytecode[ip]
        ip += 1
        else_addr = bytecode[ip]
        puts "JMPIF #{result} #{body_addr} #{else_addr}"
      when 'JMP', INSTRUCTIONS['JMP']
        ip += 1
        jmp = bytecode[ip]
        puts "JMP #{jmp}"
      when 'FUNCB', INSTRUCTIONS['FUNCB']
        puts 'FUNCB'
      when 'FUNCE', INSTRUCTIONS['FUNCE']
        puts 'FUNCE'
      when 'ARGS', INSTRUCTIONS['ARGS']
        ip += 1
        arg_size_t = bytecode[ip]
        puts "ARGS #{arg_size_t}"
      when 'FUNCC', INSTRUCTIONS['FUNCC']
        ip += 1
        arg_size_t = bytecode[ip]
        puts "FUNCC #{arg_size_t}"
      when 'RBFC', INSTRUCTIONS['RBFC']
        ip += 1
        arg_size_t = bytecode[ip]
        args = []
        (0..arg_size_t-1).each { args.push stack.pop }
        obj = stack.pop
        meth = stack.pop
        if obj && obj.respond_to?(meth)
          stack.push obj.send(meth, *args)
        else
          stack.push 0
        end

        puts "RBFC #{arg_size_t}"
      when 'RBCC', INSTRUCTIONS['RBCC']
        ip += 1
        arg_size_t = bytecode[ip]
        args = []
        (0..arg_size_t-1).each { args.push stack.pop }
        klass = stack.pop.constantize
        meth = stack.pop
        if klass
          stack.push klass.send(meth, *args)
        else
          stack.push 0
        end

        puts "RBCC #{arg_size_t}"
      else
        puts("OP CODE: 0x" + op.to_s(16))
      end

      ip += 1
    end
  end
end
