typedef enum {
  READ  = 4'b0000,
  WRITE = 4'b0001,
  //
  CONT = 4'b0100,
  HALT = 4'b0101,
  RESET_SOFT = 4'b0110,
  RESET_HARD = 4'b0111
} command_t;

