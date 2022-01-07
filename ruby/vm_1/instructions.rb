INSTRUCTIONS = {
  # Math
  'MUL' => 0x00,
  'DIV' => 0x01,
  'ADD' => 0x02,
  'SUB' => 0x03,
  # Displaying
  'PRINT' => 0x05,
  # Data push/mov operations
  'PUSH' => 0x50,
  'PUSHW' => 0x51,
  'PUSHB' => 0x52,
  'PUSHL' => 0x53,
  'MOVSM' => 0x54,
  'MOVMS' => 0x55,
  # Data comparison
  'CMP' => 0x60,
  'GT' => 0x61,
  'LT' => 0x62,
  'GTE' => 0x63,
  'LTE' => 0x64,
  # Interrupts
  'HLT' => 0x70,
  'JMPIF' => 0x71,
  'JMP' => 0x72,
  'INT' => 0x73,
  # Lambda
  'FUNCB' => 0x80,
  'FUNCE' => 0x81,
  'ARGS' => 0x82,
  'FUNCC' => 0x83,
  # Ruby functions
  'RBFC' => 0x90, # Ruby func call operand arg_size_t
  'RBCC' => 0x91, # Ruby class call operand arg_size_t

}
