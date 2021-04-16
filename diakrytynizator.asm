;;; CONSTANTS ;;;
ONE_BYTE equ 127                                    ;maximum utf-8 value coded on first byte of one byte character
TWO_BYTE equ 223                                    ;maximum utf-8 value coded on first byte of two byte character
THREE_BYTE equ 239                                  ;maximum utf-8 value coded on first byte of three byte character
FOUR_BYTE equ 247                                   ;maximum utf-8 value coded on first byte of four byte character

LCP_ONE_BYTE equ 0x7F                               ;last code point of one byte character
LCP_TWO_BYTE equ 0x7FF                              ;last code point of two byte character
LCP_THREE_BYTE equ 0xFFFF                           ;last code point of three byte character
LCP_FOUR_BYTE equ 0x10FFFF                          ;last code point of four byte character

MOD equ 0x10FF80                                    ;modulo value
SHIFT equ 0x80                                      ;character of unicode x becomes w(x - 0x80) + 0x80
LATER_SHIFT equ 2                                   ;shift for bytes 2-4 (10xxxxxx)
LATER_SHIFT_REST equ 6                              ;shift for unicode value (only 6 rightmost bits of a byte)

SYS_EXIT equ 60
SYS_READ equ 0
SYS_WRITE equ 1
STDOUT equ 1
STDIN equ 0

BUFFER_OUT_SIZE equ 4096                            ;size of bufferOut
BUFFER_IN_SIZE equ 4096                             ;size of buffer

;;; MACROS ;;;
;exits program with code in parameter %1
;modifies: rax, rdi
%macro exit 1
    mov rax, SYS_EXIT
    mov rdi, %1
    syscall
%endmacro

;;; PROGRAM ;;;
section .bss
        buffer  resb BUFFER_IN_SIZE                 ;reserve buffers for reading and writing characters
        bufferOut resb BUFFER_OUT_SIZE

section .text
	global  _start

_start:
        mov     rbp, rsp                            ;save stack pointer
        push    r13                                 ;save registers on stack
        push    r14                                 
        push    r15                                 ;r15 - number of bytes in buffer
        xor     r13, r13                            ;r13 - count of bytes in bufferOut
        mov     r14, BUFFER_IN_SIZE                 ;r14 - iterator for unread bytes in buffer

        call    validateParameters
        call    diakrytynizator

        jmp     _exit1                              ;program only ends with exit code 0 in readCharacter function

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;checks whether each parameter is an integer
;changes each integer to its modulo MOD
;saves integer to stack in place of its string
;modifies: r8, r9, r12, rdi, rdx, rax
validateParameters:
        mov     r12, MOD                            ;r12 - modulo
        mov     r8, [rbp]                           ;r8 - parameter count
        cmp     r8, 1
        je      _exit1                              ;exit with code 1 if only 1 parameter

        mov     r9, 2                               ;r9 - parameter iterator
    
_paramLoop:
        mov     rdi, [rbp + r9 * 8]                 ;move to rdi parameter from stack

        call    toInt                               ;change string to int

        xor     rdx, rdx
        div     r12                                 ;integer modulo MOD
        mov     rax, rdx

        mov     [rbp + r9 * 8], rax                 ;move integer to stack

        inc     r9
        cmp     r9, r8                              ;check if last parameter
        jbe     _paramLoop

        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;converts string to integer
;input: rdi - string of an integer
;output: rax - converted integer
;modifies: r10, rdi, rax
toInt:
        xor     rax, rax                            ;result of conversion

_intLoop:
        movzx   r10, byte [rdi]                     ;get one byte from string
        cmp     r10, 0                              ;check for end of string
        jne     _intLoopSection
        ret

_intLoopSection:
        inc     rdi                                 ;increment position in string

        cmp     r10, '9'                            ;check if character is numeric
        ja      _exit1

        cmp     r10, '0'
        jb      _exit1

        sub     r10, '0'                            ;convert character to number
        imul    rax, 10                             ;multiply old result by 10
        add     rax, r10                            ;add number to result
        jmp     _intLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;main function of the program
;changes characters from input by calculating a
;polynomial on their values
;modifies: rdi, rsi, rax
diakrytynizator:
_diaLoop:
        call    readCharacter

        mov     rdi, rax                            ;move read char
        mov     rsi, rdx                            ;move read char's length in bytes

        call    checkIfOptimized

        call    computeNewCharacter

        mov     rdi, rax

        call    writeCharacter

        jmp     _diaLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;reads characters from input till buffer is full
;or there are not more characters on input
;modifies: r14, r15
fillBuffer:
        push    rax
        push    rdi
        push    rsi
        push    rdx

        mov     rax, SYS_READ                       ;read BUFFER_IN_SIZE to buffer
        mov     rdi, STDIN
        mov     rsi, buffer
        mov     rdx, BUFFER_IN_SIZE
        syscall

        mov     r15, rax                            ;save read amount to r15

        cmp     rax, 0                              ;check for end of input
        je      _exit0

        xor     r14, r14                            ;reset unread iterator

        pop     rdx
        pop     rsi
        pop     rdi
        pop     rax

        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;reads character from input
;changes its value from utf-8 to unicode
;output: rax - read char in unicode
;        rdx - its length in bytes
;modifies: r8, r9, rax, rcx, rdi, rsi, rdx
readCharacter:
        xor     rcx, rcx                            ;rcx - shift amount

        cmp     r14, BUFFER_IN_SIZE                 ;check if r14 is out of bounds for buffer
        jne     _dontcall
        call    fillBuffer

_dontcall:
        xor     rax, rax                                              
        mov     al, [buffer + r14]                  ;move read byte to al
        mov	byte [buffer + r14], 0              ;reset place in buffer

        cmp     al, 0                               ;check if read character was 0
        jne     _after
        cmp     r14, r15                            ;if read char was 0 and it was out of bounds for buffer's element count then exit program
        jge     _exit0

_after:
        inc     r14                                 ;increment unread iterator

        mov     rdx, 1                              ;rdx - length of read character

        cmp     al, ONE_BYTE                        ;determine the length of read character by checking its value on first byte
        jbe     _readCharacterEnd                   ;program doesn't change characters coded on one byte
        inc     rdx                                 
        cmp     al, TWO_BYTE
        jbe     _readCharacterShift                 ;need to clear the length indicator
        inc     rdx
        cmp     al, THREE_BYTE
        jbe     _readCharacterShift
        inc     rdx
        cmp     al, FOUR_BYTE
        jbe     _readCharacterShift

        jmp     _exit1                              ;if no jump was made, the input is invalid

;clears character's length indicator on first byte
_readCharacterShift:
        mov     cl, dl                              ;move to cl length of char
        inc     cl                                  ;shift value is length + 1 (110xxxxx for 2, 1110xxxx for 3, etc.)
        
        shl     al, cl                              ;actual shifting
        shr     al, cl
        
        xor     r8, r8                              ;r8 - temporary register for holding read bytes
        mov     r9, 2                               ;r9 - byte iterator

;reads the rest of bytes representing a character
_readCharacterLoop:
        cmp     r14, BUFFER_IN_SIZE                 ;check if r14 is out of bounds for buffer
        jne     _dontcall1
        call    fillBuffer
        
_dontcall1:
        xor     r8b, r8b
        mov     r8b, [buffer + r14]                 ;move read byte to r8
        mov	byte [buffer + r14], 0              ;reset place in buffer


        cmp     r8b, 0                              ;check if read character was 0
        jne     _after1
        cmp     r14, r15                            ;if read char was 0 and it was out of bounds for buffer's element count then exit program
        jge     _exit0

_after1:                
        inc 	r14                                 ;increment unread iterator

        shl     r8b, LATER_SHIFT                    ;clear first two bits from read byte to get unicode (10xxxxxx)
        shr     r8b, LATER_SHIFT
        
        shl     rax, LATER_SHIFT_REST               ;shift to left to glue together unicode value
        add     al, r8b                             ;add newly calculated byte

        inc     r9
        cmp     r9, rdx                             ;check for end of character
        jbe     _readCharacterLoop

_readCharacterEnd:
        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;checks whether given character is written
;on optimal byte count by comparing
;its value to last code points
;input: rdi - unicode of char, rsi - length in bytes
checkIfOptimized:
        cmp     rsi, 1                              ;compare length of bytes
        jne     _compare2                           ;if its not equal jump to a greater value
        ret                                         ;if the length is one byte it is optimized
    
_compare2:
        cmp     rsi, 2                              ;compare length of bytes
        jne     _compare3                           ;if its not equal jump to a greater value
        cmp     rdi, LCP_ONE_BYTE                   ;compare the value of character with last code point of one byte
        jbe     _exit1                              ;if the character could be written on one byte, the input is invalid
        ret

_compare3:
        cmp     rsi, 3                              ;compare length of bytes
        jne     _compare4                           ;if its not equal jump to a greater value
        cmp     rdi, LCP_TWO_BYTE                   ;compare the value of character with last code point of two bytes
        jbe     _exit1                              ;if the character could be written on two byte, the input is invalid
        ret

_compare4:
        cmp     rdi, LCP_THREE_BYTE                 ;the length is 4 - compare the value of character with last code point of three bytes
        jbe     _exit1                              ;if the character could be written on three byte, the input is invalid
        cmp     edi, LCP_FOUR_BYTE                  ;check whether the value of character does not exceed last code point of four bytes
        ja      _exit1                              ;if does, the input is invalid
        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;changes given character to a new character
;calculated by given polynomial
;input: rdi - unicode of char, rsi - length in bytes
;output: rax - newly calculated char
;modifies: r9, r10, r11, rcx, rdx, rax
computeNewCharacter:
        push    r12                                 ;save r12 value for usage in function

        mov     r11, rdi                            ;r11 - value of character
        cmp     r11, LCP_ONE_BYTE                   ;program doesn't change characters written on one byte
        jbe     _computeEnd

        sub     rdi, SHIFT                          ;x = x - 0x80
        mov     r9, 1                               ;r9 - x^n, at start x^0 = 1
        mov     r10, 2                              ;r10 - parameter iterator
        xor     r11, r11                            ;r11 - result
        xor     rdx, rdx                            ;change to 0 before division
        mov     r12, MOD                            ;r12 - modulo
        mov     rcx, [rbp]                          ;rcx - parameter count

_computeLoop:
        mov     rax, [rbp + r10 * 8]                ;move parameter to rax
        
        mul     r9                                  ;rax = a_n * x^n

        div     r12                                 ;modulo on rax
        mov     rax, rdx                            
        xor     rdx, rdx                            ;change to 0 for future division

        add     rax, r11                            ;add old result to rax

        div     r12                                 ;modulo on rax
        mov     r11, rdx                            
        xor     rdx, rdx                            ;change to 0 for future division

        mov     rax, r9                             ;x^n to rax to update
        mul     rdi                                 ;x^n * x
        div     r12                                 ;div rax by modulo
        mov     r9, rdx                             ;remainder back to r9
        xor     rdx, rdx                            ;change to 0 for future division
        
        inc     r10
        cmp     r10, rcx                            ;check for last parameter
        jbe     _computeLoop

        add     r11, SHIFT                          ;add back subtracted 0x80

_computeEnd:
        mov     rax, r11                            ;move result to rax

        pop     r12                                 ;retrieve r12 value
        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;changes given character from unicode to utf-8
;and writes it
;input: rdi - character in unicode
;modifies: r8, r9, r10, r11, rcx, rax, rdi, rsi 
writeCharacter:
        mov	    r8, rdi                         ;r8 - input character

        mov     r9, 1                               ;find the length of input character
        cmp     r8, LCP_ONE_BYTE
        jbe     _unicodeToUTF

        inc     r9
        cmp     r8, LCP_TWO_BYTE
        jbe     _unicodeToUTF

        inc     r9
        cmp     r8, LCP_THREE_BYTE
        jbe     _unicodeToUTF

        inc     r9                                  ;r9 - length in bytes of input character

_unicodeToUTF:
        xor     r10, r10                            ;r10 - iterator for bytes with prefix 10 (10xxxxxx)
        xor     rax, rax                            ;rax - result
        xor     rcx, rcx                            ;rcx - shit amount

_unicodeToUTFLoop:
        xor     r11, r11                            ;r11 - temporary result

        inc     r10                                 
        cmp     r10, r9                             ;check for end of bytes
        je      _unicodeToUTFAdd

        mov     r11b, r8b                           ;move one byte from char to temporary result
        shr     r8, LATER_SHIFT_REST                ;clear last 6 bits of unicode
        shl     r11b, LATER_SHIFT                   ;clear first 2 bits of temporary result
        shr     r11b, LATER_SHIFT                   
        add     r11b, 128                           ;set first bit to 1 (10xxxxxx)

        shl     r11, cl                             ;shift temporary result to left to make place for next value (first set to 0)
        add     cl, 8                               ;add length of one byte to shift amount

        add     rax, r11                            ;add temporary result to result

        jmp     _unicodeToUTFLoop

;repairs first byte of utf-8
_unicodeToUTFAdd:
        mov     r11b, r8b                           ;move first byte of utf-8 to temporary result

        cmp     r9, 1                               ;if the length is 1, no need to fix (0xxxxxxx)
        je      _unicodeToUTFEnd

        add     r11b, 192                           ;if the length is 2, set first two bits to 1 (110xxxxx)
        cmp     r9, 2
        je      _unicodeToUTFEnd

        add     r11b, 32                            ;if the length is 3, set first three bits to 1 (1110xxxxx)
        cmp     r9, 3
        je      _unicodeToUTFEnd
        
        add     r11b, 16                            ;else the length is 4, set first four bits to 1 (11110xxx)

_unicodeToUTFEnd:
        mov     rcx, r9                             ;rcx = (r9 - 1) * 8
        dec     rcx
        imul    rcx, 8

        shl     r11, cl                             ;shift last byte by the amount in cl

        add     rax, r11                            ;add shifted byte to result

        mov     r8, rax                             ;r8 - character in utf-8

_writeCharacterEnd:
        mov     r10, r13                            ;r10 - new count of bytes in bufferOut
        add     r10, r9

        cmp     r10, BUFFER_OUT_SIZE                ;if new count of bytes doesn't exceed bufferOut size, jump to _ok 
        jbe     _ok

        mov     rax, SYS_WRITE                      ;if new count of bytes exceeds bufferOut size, print bufferOut
        mov     rdi, STDOUT
        mov	rsi, bufferOut
        mov     rdx, r13
        syscall

        xor     r13, r13                            ;reset count of bytes in bufferOut

_ok:
        mov     r11, r9                             ;r11 - iterator for moving character's bytes to bufferOut
        dec     r11

_wrLoop:
        mov     [bufferOut + r13 + r11], r8b        ;move each byte of r8 to bufferOut in reversed order

        cmp     r11, 0
        je      _wrEnd
        
        dec     r11
        shr     r8, 8

        jmp     _wrLoop

_wrEnd:
        add     r13, r9                             ;update count of bytes in bufferOut
        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;exits program with code 0
_exit0:                                             
        mov     rax, SYS_WRITE                      ;write bufferOut
        mov     rdi, STDOUT
        mov	rsi, bufferOut
        mov     rdx, r13
        syscall

        pop     r15
        pop     r14
        pop     r13

        exit    0

;exits program with code 1
_exit1:                                             
        mov     rax, SYS_WRITE                      ;write bufferOut
        mov     rdi, STDOUT
        mov	rsi, bufferOut
        mov     rdx, r13
        syscall

        pop     r15
        pop     r14
        pop     r13

        exit    1
