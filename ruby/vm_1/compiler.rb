require 'sxp'
require 'byebug'
require_relative 'vm'
require_relative 'instructions'

LOAD_PATH = ENV['RISPY_STD_PATH'] || File.expand_path('./', File.dirname(__FILE__))

class Array
  def self.wrap(other)
    return other if other.is_a?(Array)
    [other]
  end
end

class String
  def constantize
    Kernel.const_get self
  end
end

class Compiler
  attr_reader :bytecode, :src, :ast, :symbol_table

  def initialize
    @symbol_table = {}
    reset
    load_std
  end

  # Load standard lib
  def load_std
    stdlib = File.read './stdlib.lisp'
    compile! stdlib, true
  end

  def reset
    @bytecode = []
  end

  def compile!(src, skip_hlt=false)
    @src = src
    @ast = SXP::Reader::Scheme.read_all(src)

    # Compile each node
    ast.each do |node|
      compile_node(node)
    end

    # Push a HLT to the end if there is not one
    @bytecode << INSTRUCTIONS['HLT'] if !skip_hlt && @bytecode[@bytecode.size-1] != INSTRUCTIONS['HLT']
  end

  private

  def compile_node(node)
    if node.is_a?(Numeric)
      @bytecode += [INSTRUCTIONS['PUSH'], compile_number(node)]
      return
    elsif node.is_a?(String) # PUSHW
      compile_word(node)
      return
    elsif node.is_a?(Symbol)
      if node[0] == "'" || node[0] == "`" # quote
        return if node[1..-1].empty? # list

        val = node[1..-1]
        if val =~ /[A-Z,a-z]+/ # string
          compile_word(val)
          return
        end

        # Numeric
        val = val.include?('.') ? val.to_f : val.to_i
        @bytecode += [INSTRUCTIONS['PUSH'], val]
        return
      end

      compile_word(node) # PUSHW
      # MOVMS move variable from memory to stack
      @bytecode << INSTRUCTIONS['MOVMS']
      return
    elsif node.is_a?(TrueClass) || node.is_a?(FalseClass)
      compile_bool(node)
      return
    end

    ip = 0
    node = Array.wrap(node)

    # push empty list
    if node.empty?
      @bytecode += [INSTRUCTIONS['PUSHL'], compile_number(0)]
      return
    end

    while ip < node.size
      op = node[ip]
      case op
      when :eval
        ip += 1
        op = node[ip]
        case op
        when :`, :"'" then ip += 1
        else
          raise "Compile Error: cant eval #{op}" unless op.is_a?(String)
        end
        compile_node(node[ip])
        ip = node.size
      when :load # compile another file
        ip += 1
        file = node[ip].to_s
        begin
          code = File.read(File.join(LOAD_PATH, file))
          code_ast = SXP::Reader::Scheme.read_all(code)
          code_ast.each do |node|
            compile_node(node)
          end
        rescue Errno::ENOENT => e
          raise "Compile error: #{e}"
        end
      when :begin
        # no-op compile the statements
        node[ip+1..-1].each { |x| compile_node(x) }
        ip = node.size
      when :exit
        ip += 1
        exit_code = node[ip].to_i
        @bytecode += [INSTRUCTIONS['INT'], compile_number(exit_code)]
      when :*, :/, :+, :-
        ip += 1
        args = node[ip..-1]
        args.reverse.each { |x| compile_node(x) }
        ip = node.size
        @bytecode += [math_op_to_opcode(op), compile_number(args.size)]
      when :list
        ip += 1
        args = node[ip..-1].flatten
        ip = node.size
        args.reverse.each do |x|
          # we want to load a string onto the stack
          # a symbol would be move from memory to stack
          x = x.to_s if x.is_a?(Symbol)
          compile_node(x)
        end
        @bytecode += [INSTRUCTIONS['PUSHL'], compile_number(args.size)]
      when :quote
        # Creating a list rewrite and step pointer back
        if node[ip+1].is_a?(Array)
          node[ip] = :list
          ip -= 1
        else
          ip += 1
          v = node[ip]
          v = v.to_s if v.is_a? Symbol
          compile_node(v)
        end
      when :print, :display
        ip += 1
        compile_node(node[ip])
        ip += 1
        @bytecode += [INSTRUCTIONS['PRINT']]
      when :define, :let
        ip += 1
        func = (node[ip+1].is_a?(Array) && node[ip+1][0] == :lambda) ? 1 : 0
        symbol_table[node[ip].to_s] = [@bytecode.size, func]
        compile_node(node[ip].to_s) # compile the word
        ip += 1
        compile_node(node[ip]) # compile the value
        @bytecode << INSTRUCTIONS['MOVSM'] # Move stack value to memory
      when :'=', :>, :<, :>=, :<=
        ip += 1
        args = node[ip..-1]
        args.reverse.each { |x| compile_node(x) }
        ip = args.size
        @bytecode += [comparison_to_opcode(op), compile_number(args.size)]
      when :if
        ip += 1
        compile_node(node[ip]) # compile conditonal
        ip += 1
        # JMPIF, BODY-ADDR, ELSE-ADDR
        @bytecode += [INSTRUCTIONS['JMPIF'], -1, -1]
        body_ip_idx = @bytecode.size # The next instruction should be the body
        body_addr_idx = @bytecode.size - 2
        @bytecode[body_addr_idx] = compile_number(body_ip_idx) # Compile the jump index to the body-addr for JMPIF
        else_addr_idx = @bytecode.size - 1
        compile_node(node[ip]) # compile the body
        ip += 1
        @bytecode += [INSTRUCTIONS['JMP'], -1] # add a jump to the end of the if to jump to the end of th else
        jmp_addr_idx = @bytecode.size - 1
        else_ip_idx = @bytecode.size # the else or past the else should be the next instruction index
        @bytecode[else_addr_idx] = compile_number(else_ip_idx) # assign the jmp index to the else-addr for JMPIF

        compile_node(node[ip]) if ip < node.size # compile the else or next instruction past the if
        # the next instruction is the end
        @bytecode[jmp_addr_idx] = compile_number(@bytecode.size)
      when :lambda
        ip += 1
        args = node[ip]
        ip += 1
        # Because a function gets compiled and stored in memory its possible we compile
        # if statements that later jump over the function bytecode length because it gets put into memory
        # so the VM can execute new instructions but recall old methods/values.
        # long story short backup the current bytecode and reset the bytecode array so calculations
        # are based on the functions bytecode
        args.each { |x| compile_node(x.to_s) }  # COMPILE ARGS
        @bytecode << INSTRUCTIONS['FUNCB'] # BEGIN FUNC
        @bytecode += [INSTRUCTIONS['ARGS'], args.size]
        # Do the backup here
        backup = @bytecode
        @bytecode = []
        compile_node(node[ip]) # COMPILE FUNC BODY
        @bytecode = backup + @bytecode # reset the bytecode scope
        @bytecode << INSTRUCTIONS['FUNCE'] # END FUNC
      when :"rb-call"
        ip += 1
        # compile the method name
        meth = node[ip]
        compile_node(meth.to_s)
        ip += 1
        compile_node(node[ip]) # compile the object
        ip += 1
        args = node[ip..-1]
        ip = node.size
        args.reverse.each { |x| compile_node(x) } # compile the args to send
        @bytecode += [INSTRUCTIONS['RBFC'], args.size]
      when :"rb-class-call"
        ip += 1
        # compile the method name
        meth = node[ip]
        compile_node(meth.to_s)
        ip += 1
        compile_node(node[ip].to_s) # compile class string
        ip += 1
        args = node[ip..-1]
        ip = node.size
        args.reverse.each { |x| compile_node(x) } # compile the args to send
        @bytecode += [INSTRUCTIONS['RBCC'], args.size]
      else
        if op.is_a?(Symbol) # Function CALL
          func = symbol_table[op.to_s]
          raise "Compile Error: Unknown function #{op.to_s}" if func.nil? || func[1] == 0
          ip += 1
          args = node[ip..-1]
          ip = node.size
          # compile the agrs first so they exist on the stack
          args.each { |x| compile_node(x) }
          # compile the function name so it exists on the stack
          compile_node(op.to_s)
          @bytecode += [INSTRUCTIONS['FUNCC'], compile_number(args.size)] # call the function
        else
          raise "Compiler Error: Unkown type #{op}"
        end
      end

      ip += 1
    end
  end

  def compile_number(num)
    num.to_s(16).to_i(16)
  end

  def compile_word(word)
    word = word.to_s.bytes.reverse
    wsize = word.size
    word.each do |byte|
      @bytecode += [INSTRUCTIONS['PUSH'], byte]
    end
    @bytecode += [INSTRUCTIONS['PUSHW'], wsize]

    wsize
  end

  def compile_bool(bool)
    bool_t = compile_number(1) if bool
    bool_t ||= compile_number(0)
    @bytecode += [INSTRUCTIONS['PUSHB'], bool_t]
  end

  def comparison_to_opcode(op)
    case op
    when :"=" then INSTRUCTIONS['CMP']
    when :>   then INSTRUCTIONS['GT']
    when :<   then INSTRUCTIONS['LT']
    when :>=  then INSTRUCTIONS['GTE']
    when :<=  then INSTRUCTIONS['LTE']
    else
      raise "Unknown opcode for comparison operation #{op}"
    end
  end

  def math_op_to_opcode(op)
    case op
    when :* then INSTRUCTIONS['MUL']
    when :/ then INSTRUCTIONS['DIV']
    when :+ then INSTRUCTIONS['ADD']
    when :- then INSTRUCTIONS['SUB']
    else
      raise "Unknow opcode for math operator #{op}"
    end
  end
end
