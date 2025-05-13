# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

	EXPLOSION = 64			    # ASCII code of EXPLOSION symbol '@'
	SPACE = 32			        # ASCII code of SPACE symbol ' '
	CROSSHAIRS = 43			    # ASCII code of CROSSHAIR symbol '+'
	CROSSHAIRS_INIT_X = 40		# starting position X of CROSSHAIR
	CROSSHAIRS_INIT_Y = 12		# starting position Y of CROSSHAIR

	X_MIN_POS = 0			# left most position of X
	X_MAX_POS = 79			# right most position of X
	Y_MIN_POS = 0			# top most position of Y
	Y_MAX_POS = 24			# bottom most position of Y

	ROW_OFFSET = 160		# memory offset of 1 row
	COLUMN_OFFSET = 2		# memory offset of 1 column
	BASE_ROW_OFFSET = 3840	# memory offset of 24 rows
	SHIFT_16_BITS = 16		# shift right/left offset = 16 bits

	FIRST_BASE = 18			# 1st base X position
	SECOND_BASE = 38		# 2nd base X position
	THIRD_BASE = 58			# 3rd base X position
	BASE_1_FINISH = 23		# end X position of 1st base
	BASE_2_FINISH = 43		# end X position of 2nd base

	MALLOC_MEMORY_BITS = 33		# malloc memory bits --- 33-bit

	FIRST_BASE_ALIVE = 0x000000FF	# check 1st base alive const
	SECOND_BASE_ALIVE = 0x0000FF00	# check 2nd base alive const
	THIRD_BASE_ALIVE = 0x00FF0000	# check 3rd base alive const

# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	    # Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	    # Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	    # Picture of a dead base
crosshairs_x:		.long 0x0	        # X-position of the crosshairs
crosshairs_y:		.long 0x0	        # Y-position of the crosshairs
.text

# void mp1_poke(void);
# You can use this function to write to video memory.
# 
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet

mp1_rtc_tasklet:
  PUSHL %EBP
  MOVL  %ESP, %EBP

  PUSHL %EAX			#callee save registers
  PUSHL %ECX
  PUSHL %EDX
  PUSHL %EBX
  PUSHL %ESI
  PUSHL %EDI
  CALL update_missiles
  POPL  %EDI
  POPL  %ESI
  POPL  %EBX
  POPL  %EDX
  POPL  %ECX
  POPL  %EAX

  PUSHL %EAX			#callee save registers
  PUSHL %ECX
  PUSHL %EDX
  PUSHL %EBX
  PUSHL %ESI
  PUSHL %EDI
  CALL  Draw_Base
  POPL  %EDI
  POPL  %ESI
  POPL  %EBX
  POPL  %EDX
  POPL  %ECX
  POPL  %EAX

  PUSHL %EAX			#callee save registers
  PUSHL %ECX
  PUSHL %EDX
  PUSHL %EBX
  PUSHL %ESI
  PUSHL %EDI
  CALL  Draw_Crosshairs
  POPL  %EDI
  POPL  %ESI
  POPL  %EBX
  POPL  %EDX
  POPL  %ECX
  POPL  %EAX

  leave
  ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
  MOVL 8(%ESP), %EBX
  CMPL $0, %EBX
  JL   Invalid_CMD
  CMPL $4, %EBX
  JG   Invalid_CMD
  JMP  *JUMP_TABLE(,%EBX,4) 
  JMP  Return_0
  
  Invalid_CMD:
    MOVL $-1, %EAX
  
  Return_0:
    ret

JUMP_TABLE:
  .long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame

# ----------------- Functions private to this file -------------------

# void update_missiles()
# Traverse the missile list and update the information of the missiles
# such as position, exploded or not, out of grid, which char to display, remove missile ...
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

update_missiles:
  PUSHL %EBP
  MOVL  %ESP, %EBP
  PUSHL %EBX
  PUSHL %ESI
  PUSHL %EDI

  MOVL mp1_missile_list, %EBX

  Traverse_Missile_List:
    CMPL $0, %EBX
    JE   Finish_Traverse_Missile_List

    #Erase_Missile
    MOVB  $SPACE, %CL				    # %CL <- ' ' to clear the missile
    MOVL  X(%EBX), %ESI				    # %ESI <- X position of the missile
    SHRL  $SHIFT_16_BITS, %ESI			# shift right 16-bit to get X position of the missile
    IMULL $COLUMN_OFFSET, %ESI, %EAX    # %EAX <- column offset of the memory address
    MOVL  Y(%EBX), %ESI				    # %ESI <- Y position of the missile
    SHRL  $SHIFT_16_BITS, %ESI			# shift right 16-bit to get Y position of the missile
    IMULL $ROW_OFFSET, %ESI			    # %ESI <- row offset of the memory address
    ADDL  %ESI, %EAX				    # %EAX <- row & column offset of the memory address
    PUSHL %EBX					        # save content in %EBX
    PUSHL %EDX
    CALL  mp1_poke				        # draw char
    POPL  %EDX
    POPL  %EBX					        # retain content in %EBX

    CMPL $0, EXPLODED(%EBX)
    JNE  Draw_Exploded_Missile

    #Check_Missile_Position:
    MOVL X(%EBX), %ESI				# %ESI <- X position of the missile
    ADDL VX(%EBX), %ESI				# %ESI <- X + dX
    SHRL $SHIFT_16_BITS, %ESI		# %ESI <- X position of the missile Top 16-bit
    CMPL $X_MIN_POS, %ESI			# check X position with X_min
    JL   Remove_Missile				# remove missile since out of range
    CMPL $X_MAX_POS, %ESI			# check X position with X_max
    JG   Remove_Missile				# remove missile since out of range

    MOVL Y(%EBX), %ESI				# %ESI <- Y position of the missile
    ADDL VY(%EBX), %ESI				# %ESI <- Y + dY
    SHRL $SHIFT_16_BITS, %ESI		# %ESI <- Y position of the missile Top 16-bit
    CMPL $Y_MIN_POS, %ESI			# check Y position with Y_min
    JL   Remove_Missile				# remove missile since out of range
    CMPL $Y_MAX_POS, %ESI			# check Y position with Y_max
    JG   Remove_Missile				# remove missile since out of range

    #Update_Missile_Position:
    MOVL VX(%EBX), %ESI				# %ESI <- dX
    ADDL %ESI, X(%EBX)				# X position <- X + dX
    MOVL VY(%EBX), %ESI				# %ESI <- dY
    ADDL %ESI, Y(%EBX)				# Y position <- Y + dY
    
    #Check_Missile_Exploded
    MOVL X(%EBX), %ESI
    SHRL $SHIFT_16_BITS, %ESI
    CMPL %ESI, DEST_X(%EBX)
    JNE  Draw_Missile
    
    MOVL Y(%EBX), %ESI
    SHRL $SHIFT_16_BITS, %ESI
    CMPL %ESI, DEST_Y(%EBX)
    JNE  Draw_Missile

    Draw_Exploded_Missile:
      MOVB  $EXPLOSION, %CL			        # %CL <- missile explosion symbol
      MOVL  X(%EBX), %ESI			        # %ESI <- X position of the missile
      SHRL  $SHIFT_16_BITS, %ESI		    # shift right 16-bit to get X position of the missile
      IMULL $COLUMN_OFFSET, %ESI, %EAX		# %EAX <- column offset of the memory address
      MOVL  Y(%EBX), %ESI			        # %ESI <- Y position of the missile
      SHRL  $SHIFT_16_BITS, %ESI		    # shift right 16-bit to get Y position of the missile
      IMULL $ROW_OFFSET, %ESI			    # %ESI <- row offset of the memory address
      ADDL  %ESI, %EAX				        # %EAX <- row & column offset of the memory address
      PUSHL %EBX				            # save content in %EBX
      PUSHL %EDX
      CALL  mp1_poke				        # draw char
      POPL  %EDX
      POPL  %EBX				            # restore content in %EBX

      PUSHL %EBX				# save content in %EBX
      CALL  missile_explode		# call missile_explode
      POPL  %EBX				# restore content in %EBX

      CMPL  $0, %EAX
      JE    Decrement_Exploded_Field
      PUSHL %EBX				# restore content in %EBX
      CALL  mp1_notify_user		# call mp1_notify_user
      POPL  %EBX				# restore content in %EBX
      
    Decrement_Exploded_Field:
      ADDL  $-1, EXPLODED(%EBX)
      CMPL  $0, EXPLODED(%EBX)
      JE    Erase_Exploded_Missile

    MOVB  $EXPLOSION, %CL			    # %CL <- ' ' to clear the missile
    MOVL  X(%EBX), %ESI				    # %ESI <- X position of the missile
    SHRL  $SHIFT_16_BITS, %ESI			# shift right 16-bit to get X position of the missile
    IMULL $COLUMN_OFFSET, %ESI, %EAX	# %EAX <- column offset of the memory address
    MOVL  Y(%EBX), %ESI				    # %ESI <- Y position of the missile
    SHRL  $SHIFT_16_BITS, %ESI			# shift right 16-bit to get Y position of the missile
    IMULL $ROW_OFFSET, %ESI			    # %ESI <- row offset of the memory address
    ADDL  %ESI, %EAX				    # %EAX <- row & column offset of the memory address
    PUSHL %EBX					        # save content in %EBX
    PUSHL %EDX
    CALL  mp1_poke				        # draw char
    POPL  %EDX
    POPL  %EBX					        # retain content in %EBX

    JMP Next_Missile
      
    Erase_Exploded_Missile:
      MOVB  $SPACE, %CL				    # %CL <- ' ' to clear the missile
      MOVL  X(%EBX), %ESI			    # %ESI <- X position of the missile
      SHRL  $SHIFT_16_BITS, %ESI		# shift right 16-bit to get X position of the missile
      IMULL $COLUMN_OFFSET, %ESI, %EAX  # %EAX <- column offset of the memory address
      MOVL  Y(%EBX), %ESI			    # %ESI <- Y position of the missile
      SHRL  $SHIFT_16_BITS, %ESI		# shift right 16-bit to get Y position of the missile
      IMULL $ROW_OFFSET, %ESI			# %ESI <- row offset of the memory address
      ADDL  %ESI, %EAX				    # %EAX <- row & column offset of the memory address
      PUSHL %EBX				        # save content in %EBX
      PUSHL %EDX
      CALL  mp1_poke				    # draw char
      POPL  %EDX
      POPL  %EBX				        # retain content in %EBX

    Remove_Missile:
      CMPL mp1_missile_list, %EBX
      JE   Remove_Head
      
      MOVL mp1_missile_list, %ESI

      Find_Node_Remove:
        CMPL NEXT(%ESI), %EBX	# compare %ESI next with %EBX node want to remove
        JE   Remove
        MOVL NEXT(%ESI), %ESI
        JMP  Find_Node_Remove

      Remove:
        MOVL  NEXT(%EBX), %EDI	# %EDI <- %EBX next, node want to remove next
        MOVL  %EDI, NEXT(%ESI)	# %ESI next <- node want to remove next
        PUSHL %EDI
        PUSHL %EBX
        CALL  mp1_free
        POPL  %EBX
        POPL  %EDI
        MOVL  %EDI, %EBX	    # %EBX <- %EDI, node want to remove next
        JMP   Traverse_Missile_List

      Remove_Head:
        MOVL  NEXT(%EBX), %ESI			# %ESI <- %EBX next, head next
        MOVL  %ESI, mp1_missile_list	# mp1_missile_list <- %ESI, old head next
        PUSHL %EBX
        CALL  mp1_free				    # free head missile memory
        POPL  %EBX
        MOVL  mp1_missile_list, %EBX	# %EBX <- mp1_missile_list, new head
        JMP   Traverse_Missile_List

    Draw_Missile:
      MOVB  C(%EBX), %CL			    # %CL <- missile symbol
      MOVL  X(%EBX), %ESI			    # %ESI <- X position of the missile
      SHRL  $SHIFT_16_BITS, %ESI		# shift right 16-bit to get X position of the missile
      IMULL $COLUMN_OFFSET, %ESI, %EAX	# %EAX <- column offset of the memory address
      MOVL  Y(%EBX), %ESI			    # %ESI <- Y position of the missile
      SHRL  $SHIFT_16_BITS, %ESI		# shift right 16-bit to get Y position of the missile
      IMULL $ROW_OFFSET, %ESI			# %ESI <- row offset of the memory address
      ADDL  %ESI, %EAX				    # %EAX <- row & column offset of the memory address
      PUSHL %EBX				        # save content in %EBX
      PUSHL %EDX
      CALL  mp1_poke				    # draw char
      POPL  %EDX
      POPL  %EBX				        # retain content in %EBX
      JMP   Next_Missile

    Next_Missile:
      MOVL NEXT(%EBX), %EBX
      JMP  Traverse_Missile_List

  Finish_Traverse_Missile_List:
    POPL %EDI
    POPL %ESI
    POPL %EBX
    leave
    ret

# void Draw_Base()
# Draw 3 bases on the screen depended on their corresponding base status bit
# 1 - base_alive, 0 - dead_base
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

Draw_Base:
  PUSHL %EBP
  MOVL  %ESP, %EBP
  PUSHL %EBX
  PUSHL %ESI
  PUSHL %EDI

  #Check_Base_1				    # Check the 1st Base
    MOVL $FIRST_BASE, %ESI		# %ESI <- the X position of the 1st base
    MOVL $0, %EDI			    # clear %EDI to use as loop counter

    MOVL base_alive, %EBX		# %EBX <- base_alive array
    CMPB $0, %BL			    # check if the 1st base is alive
    JE   Dead_Base			    # the 1st base is dead base, jump to Dead_Base

    LEAL base_pic, %EBX			# %EBX <- the starting address of alive base picture
    JMP  Draw_Full_Base			# jump to Draw_Full_Base to draw the entire base

  Check_Base_2:				    # Check the 2nd Base
    MOVL $SECOND_BASE, %ESI		# %ESI <- the X position of the 2nd base
    MOVL $0, %EDI			    # clear %EDI to use as loop counter

    MOVL base_alive, %EBX		# %EBX <- base_alive array
    CMPB $0, %BH			    # check if the 2nd base is alive
    JE   Dead_Base			    # the 2nd base is dead base, jump to Dead_Base

    LEAL base_pic, %EBX			# %EBX <- the starting address of alive base picture
    JMP  Draw_Full_Base			# jump to Draw_Full_Base to draw the entire base

  Check_Base_3:				    # Check the 3rd Base
    MOVL $THIRD_BASE, %ESI		# %ESI <- the X position of the 3rd base
    MOVL $0, %EDI			    # clear %EDI to use as loop counter

    MOVL base_alive, %EBX		# %EBX <- base_alive array
    SHRL $SHIFT_16_BITS, %EBX	# shift the higher 16-bit into %BX
    CMPB $0, %BL			    # check if the 3rd base is alive
    JE   Dead_Base			    # the 3rd base is dead base, jump to Dead_Base

    LEAL base_pic, %EBX 		# %EBX <- the starting address of alive base picture
    JMP  Draw_Full_Base			# jump to Draw_Full_Base to draw the entire base
  
  Dead_Base:				
    LEAL dead_base_pic, %EBX	# %EBX <- the starting address of dead base picture

  Draw_Full_Base:
    MOVB (%EBX), %CL			        # Load the char to display into %CL
    IMULL $COLUMN_OFFSET, %ESI, %EAX	# %EAX <- the column offset of memory address
    ADDL  $BASE_ROW_OFFSET, %EAX	    # add row offset of memory address to %EAX

    PUSHL %EDX
    CALL  mp1_poke			    # draw the char
    POPL  %EDX

    INCL %EBX				    # increment the address of base picture
    INCL %ESI				    # increment the X position of the base
    INCL %EDI				    # increment the loop counter
    
    CMPL $4, %EDI			    # check if the loop has already executed 5 times
    JLE  Draw_Full_Base			# if NO, execute loop again

  CMPL $BASE_1_FINISH, %ESI		# check which base to draw next
  JE   Check_Base_2			    # draw 2nd base next

  CMPL $BASE_2_FINISH, %ESI		# check which base to draw next
  JE   Check_Base_3			    # draw 3rd base next

  POPL %EDI
  POPL %ESI
  POPL %EBX
  leave
  ret

# void Draw_Base()
# Draw the crosshairs on the screen for user to aim
# crosshairs - '+'
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

Draw_Crosshairs:
  PUSHL %EBP
  MOVL  %ESP, %EBP
  PUSHL %EBX
  PUSHL %ESI
  PUSHL %EDI

  MOVB  $CROSSHAIRS, %CL			        # %CL <- '+' as crosshairs symbol
  
  IMULL $ROW_OFFSET, crosshairs_y, %EAX		# %EAX <- row offset of memory address
  IMULL $COLUMN_OFFSET, crosshairs_x, %EBX	# %EBX <- column offset of memory address
  ADDL  %EBX, %EAX				            # %EAX <- row & column offset of memory address

  PUSHL %EDX
  CALL  mp1_poke    # draw the char '+'
  POPL  %EDX

  POPL  %EDI
  POPL  %ESI
  POPL  %EBX
  leave
  ret

# int mp1_ioctl_movexhairs(unsigned long xhair_delta_packed)
# move crosshairs in 4 directions, and check if the crosshairs is out of the grid
# keep the crosshairs move inside the grid with boundary check
# Inputs   : unsigned long xhair_delta_packed - store delta_y in [31:16], and store delta_x in [15:0]
# Outputs  : always return integer 0
# Registers: Standard C calling convention

mp1_ioctl_movexhairs:
  PUSHL %EBP
  MOVL  %ESP, %EBP
  PUSHL %EBX
  PUSHL %ESI
  PUSHL %EDI
  
  MOVB  $SPACE, %CL				            # remove the crosshairs
  IMULL $ROW_OFFSET, crosshairs_y, %EAX		# %EAX <- the row offset of memory address
  IMULL $COLUMN_OFFSET, crosshairs_x, %EBX 	# %EBX <- the column offset of memory address
  ADDL  %EBX, %EAX				            # %EAX <- row & column offset of memory address
  
  PUSHL %EDX
  CALL  mp1_poke    # draw the char ' '
  POPL  %EDX

  # Update crosshairs position
  # crosshairs x position = crosshairs_x + [15: 0]xhair_delta_packed (delta_x)
  # crosshairs y position = crosshairs_y + [31:16]xhair_delta_packed (delta_y)

  MOVL   8(%EBP), %EBX				# %EBX <- 32-bit xhair_delta_packed
  ANDL   $0x0000FFFF, %EBX			# remove [31:16] delta_y in %EBX
  MOVSWL %BX, %EBX				    # %EBX <- sign extend %BX delta_x
  ADDL   %EBX, crosshairs_x			# M[crosshairs_x] <- M[crosshairs_x] + %BX
						            # new crosshairs_x = crosshairs_x + delta_x

  MOVL 8(%EBP), %EBX				# %EBX <- 32-bit xhair_delta_packed
  SARL $SHIFT_16_BITS, %EBX			# %EBX <- arithmetic shift right [31:16]xhair_delta_packed
  ADDL %EBX, crosshairs_y			# M[crosshairs_y] <- M[crosshairs_y] + %BX
						            # new crosshairs_y = crosshairs_x + delta_y

  #Boundary_Check:				    # Boundary_Check
    CMPL $X_MIN_POS, crosshairs_x	# check if crosshairs_x is out of range on the left
    JGE  Right_Boundary_Check 		# jump to Out_of_Range_Left
    MOVL $X_MIN_POS, crosshairs_x	# assign min X position to crosshairs_x

  Right_Boundary_Check:
    CMPL $X_MAX_POS, crosshairs_x	# check if crosshairs_x is out of range on the right
    JLE  Top_Boundary_Check 		# jump to Out_of_Range_Right
    MOVL $X_MAX_POS, crosshairs_x	# assign max X position to crosshairs_x

  Top_Boundary_Check:
    CMPL $Y_MIN_POS, crosshairs_y	# check if crosshairs_x is out of range on the top
    JGE  Bottom_Boundary_Check 		# jump to Out_of_Range_Top
    MOVL $Y_MIN_POS, crosshairs_y	# assign min Y position to crosshairs_y

  Bottom_Boundary_Check:
    CMPL $Y_MAX_POS, crosshairs_y	# check if crosshairs_x is out of range on the bottom
    JLE   Boundary_Check_Pass		# jump to Boundary_Check_Pass
    MOVL $Y_MAX_POS, crosshairs_y	# assign max Y position to crosshairs_y

  Boundary_Check_Pass:
    MOVL $0, %EAX				    # return 0
    POPL %EDI
    POPL %ESI
    POPL %EBX
    leave
    ret

# void startgame(unsifned long ignore)
# initialize all the global variables here to start the game
# Inputs   : long ignore - not used
# Outputs  : none
# Registers: Standard C calling convention

mp1_ioctl_startgame:
  MOVL  $0, mp1_missile_list			    # initialize mp1_missile_list to 0
  MOVL  $0x00FFFFFF, base_alive			    # initialize base_alive to 0
  MOVL  $0, mp1_score				        # initialize mp1_score to 0
  MOVL  $CROSSHAIRS_INIT_X, crosshairs_x	# initialize the starting X position of crosshairs
  MOVL  $CROSSHAIRS_INIT_Y, crosshairs_y	# initialize the starting Y position of crosshairs
  ret

# int mp1_ioctl_addmissile(struct missile* user missile)
# add missile to the mp1_missile_list
# allocate memory and copy from user, finally free the allocate memory
# Inputs   : struct missile* user missile - pointer to the starting memory of missile struct
# Outputs  : return 0 - copy successfully, return -1 - copy fail
# Registers: Standard C calling convention

mp1_ioctl_addmissile:
  PUSHL %EBP
  MOVL  %ESP, %EBP
  PUSHL %EBX
  PUSHL %ESI
  PUSHL %EDI

  MOVL 8(%EBP), %EBX			# %EBX <- pointer to struct missile
  CMPL $0, %EBX				    # check if it's a null pointer
  JE   Null_Pointer_Copy_Fail

  PUSHL $MALLOC_MEMORY_BITS		# push arg to stack
  CALL  mp1_malloc			    # call function mp1_malloc
  ADDL  $4, %ESP			    # restore the stack pointer
  MOVL  %EAX, %ESI			    # %ESI <- pointer to allocate memory
  CMPL  $0, %ESI			    # check it it's a null pointer
  JE    Null_Pointer_Copy_Fail

  PUSHL $MALLOC_MEMORY_BITS		# push arg to stack
  PUSHL %EBX				    # *from %EBX <- pointer to struct missile
  PUSHL %ESI				    # *to   %ESI <- pointer to allocate memory
  CALL  mp1_copy_from_user		# call function mp1_copy_from_user
  ADDL  $12, %ESP			    # restore the stack pointer
  CMPL  $0, %EAX			    # check if copy successfully
  JNE   Null_Pointer_Copy_Fail

  MOVL  mp1_missile_list, %EDI	# %EDI <- head of missile_list
  MOVL  %EDI, NEXT(%ESI)		# put head of missile_list to new allocate memory NEXT
  MOVL  %ESI, mp1_missile_list	# new allocate memory <- head of missile_list

  #Copy_From_User_Success:
  MOVL  $0, %EAX			    # copy from user success, return 0
  POPL  %EDI
  POPL  %ESI
  POPL  %EBX
  leave
  ret

  Null_Pointer_Copy_Fail:
    PUSHL %ESI				# push arg to stack		
    CALL  mp1_free			# free allocate memory
    POPL  %ESI
    MOVL  $-1, %EAX			# Copy_Fail, return -1
    POPL  %EDI
    POPL  %ESI
    POPL  %EBX
    leave
    ret

# int mp1_ioctl_getstatus(unsigned long* user status)
# get the status of the game, such as the status of the 3 base and the user's points
# Inputs   : unsigned long* user status - pointer to the data game status
# Outputs  : return 0 - copy successfully, return -1 - copy fail
# Registers: Standard C calling convention

mp1_ioctl_getstatus:
  PUSHL %EBP
  MOVL  %ESP, %EBP
  PUSHL %EBX
  PUSHL %ESI
  PUSHL %EDI

  MOVL 8(%EBP), %EBX		# %EBX <- user_status
  MOVL $0, %EDI				# %EDI <- 0, clear %EDI

  # Check_First_Base_Life
  MOVL $FIRST_BASE_ALIVE, %ESI		# %ESI <- 0x000000FF
  ANDL base_alive, %ESI			    # check if the 1st base is alive
  CMPL $FIRST_BASE_ALIVE, %ESI		#
  JNE  Check_Second_Base_Life
  ADDL $1, %EDI				        # 1st base is alive, store a 1 at the 0th bit of %EDI

  Check_Second_Base_Life:
  MOVL $SECOND_BASE_ALIVE, %ESI		# %ESI <- 0x0000FF00
  ANDL base_alive, %ESI			    # check if the 2nd base is alive
  CMPL $SECOND_BASE_ALIVE, %ESI		#
  JNE  Check_Third_Base_Life
  ADDL $2, %EDI				        # 2nd base is alive, store a 1 at the 1st bit of %EDI
  
  Check_Third_Base_Life:
  MOVL $THIRD_BASE_ALIVE, %ESI		# %ESI <- 0x00FF0000
  ANDL base_alive, %ESI			    # check if the 3rd base is alive
  CMPL $THIRD_BASE_ALIVE, %ESI		#
  JNE  Update_Score_Base_Status
  ADDL $4, %EDI				        # 3rd base is alive, store a 1 at the 2nd bit of %EDI

  Update_Score_Base_Status:
    SHLL   $SHIFT_16_BITS, %EDI		# shift %EDI left 16-bit to move the base status to 16th, 17th, 18th bit
    MOVZWL mp1_score, %ESI		    # %ESI <- current mp1_score
    ADDL   %ESI, %EDI			    # %EDI <- [18:16] base_status + [15:0] mp1_score

    PUSHL %EDI				        # push %EDI on to stack with the above data
    MOVL  %ESP, %ESI			    # %ESI <- %ESP, %ESI points to the memory address of above data
    PUSHL $4				        # 4 bytes
    PUSHL %ESI				        # *from
    PUSHL %EBX				        # *to
    CALL  mp1_copy_to_user
    POPL  %EBX				        # restore stack pointer
    POPL  %ESI				        #
    ADDL  $4, %ESP			        #
    POPL  %EDI				        #

  CMPL $0, %EAX
  JNE   Copy_To_User_Fail

  #Copy_To_User_Success
  MOVL $0, %EAX				        # copy to user success, return 0
  POPL %EDI
  POPL %ESI
  POPL %EBX
  leave 
  ret  

  Copy_To_User_Fail:
    MOVL $-1, %EAX			        # copy to user fail, return -1
    POPL %EDI
    POPL %ESI
    POPL %EBX
    leave 
    ret

# int mp1_ioctl_endgame((unsigned long ignore)
# end the game, and free all the memory allocated
# free the entire mp1_missile_list
# Inputs   : (unsigned long ignore - not used
# Outputs  : return
# Registers: Standard C calling convention

mp1_ioctl_endgame:
  PUSH  %EBP
  MOVL  %ESP, %EBP
  PUSHL %EBX
  PUSHL %ESI
  PUSHL %EDI
  
  MOVL mp1_missile_list, %EBX		# %EBX <- head of mp1_missile_list

  Free_LinkedList:
    CMP  $0, %EBX
    JE   Finish_Free_LinkedList		# check if head of mp1_missile_list is NULL PTR
    MOVL NEXT(%EBX), %ESI		    # %ESI <- next missile of mp1_missile_list
    PUSH %EBX
    CALL mp1_free
    POPL %EBX
    MOVL %ESI, %EBX			        # %EBX <- %ESI next missile of mp1_missile_list
    JMP  Free_LinkedList		    # jump back to Free_LinkedList

  Finish_Free_LinkedList:
    POPL %EDI
    POPL %ESI
    POPL %EBX
    leave
    ret
