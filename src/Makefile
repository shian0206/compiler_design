CC = g++

LEX_SOURCE = lexer.l
YACC_SOURCE = parser.y
SYMBOL_TABLE_SOURCE = symboltable.cpp

all: compile

compile: yacc lex $(SYMBOL_TABLE_SOURCE)
	$(CC) y.tab.cpp lex.yy.cpp $(SYMBOL_TABLE_SOURCE) -o parser

yacc: $(YACC_SOURCE)
	yacc -d -t -v $(YACC_SOURCE) -o y.tab.cpp

lex: $(LEX_SOURCE) y.tab.hpp
	lex -o lex.yy.cpp $(LEX_SOURCE)

.PHONY: clean

clean:
	- rm -f y.tab.*
	- rm -f *.o
	- rm -f lex.yy.*
	- rm -f *.output
	- rm -f parser
