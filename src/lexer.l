%{
#include "symboltable.h"
#include "y.tab.hpp"

#define LIST strcat(buf, yytext)
#define token(t) {LIST; printf("<'%s'>\n", #t); return t;}
#define tokenInteger(t, i) {LIST; printf("<%s:%d>\n", #t, i); return INTEGER_LITERAL;}
#define tokenString(t, s) {LIST; printf("<%s:%s>\n", #t, s); return STRING_LITERAL;}
#define tokenReal(t, r) {LIST; printf("<%s:%f>\n", #t, r); return REAL_LITERAL;}
int linenum = 1;
char buf[MAX_NAME];


%}

%option noyywrap
%x COMMENT LINE_COMMENT

delimiter       "."|","|":"|";"|"("|")"|"["|"]"|"{"|"}"
operator        "++"|"--"|"*"|"/"|"%"|"+"|"-"|"<"|"<="|"=="|"=>"|">"|"!="|"!"|"&&"|"||"|"="

%%

<INITIAL>[ \t\r]+ { LIST; }

<INITIAL>"\n" {
    LIST;
    printf("%d: %s", linenum, buf); 
    linenum++; 
    buf[0] = '\0'; 
}

<INITIAL>"/*"                 { LIST; BEGIN(COMMENT); }
<INITIAL>"//" { LIST; BEGIN(LINE_COMMENT); }
<LINE_COMMENT>. {LIST;}
<LINE_COMMENT>"\n" {
    LIST;
    printf("%d: %s", linenum, buf); 
    linenum++; 
    buf[0] = '\0'; 
    BEGIN(INITIAL);
    }

<COMMENT>[^\n] { LIST; }
<COMMENT>"\n" {
    LIST;
    printf("%d: %s", linenum, buf);
    linenum++;
    buf[0] = '\0';
    }
<COMMENT>"*/" { LIST; BEGIN(INITIAL); }


<INITIAL>"bool"                 { token(BOOL); }
<INITIAL>"break"                { token(BREAK); }
<INITIAL>"case"                 { token(CASE); }
<INITIAL>"char"                 { token(CHAR); }
<INITIAL>"const"                { token(CONST); }
<INITIAL>"continue"             { token(CONTINUE); }
<INITIAL>"default"              { token(DEFAULT); }
<INITIAL>"do"                   { token(DO); }
<INITIAL>"else"                 { token(ELSE); }
<INITIAL>"extern"               { token(EXTERN); }
<INITIAL>"false" {
    yylval.bVal = false;
    LIST;
    printf("<bool:%s>\n", yytext);
    return BOOL_LITERAL;
}
<INITIAL>"for"                  { token(FOR); }
<INITIAL>"foreach"              { token(FOREACH); }
<INITIAL>"if"                   { token(IF); }
<INITIAL>"print"                { token(PRINT); }
<INITIAL>"println"              { token(PRINTLN); }
<INITIAL>"read"                 { token(READ); }
<INITIAL>"return"               { token(RETURN); }
<INITIAL>"switch"               { token(SWITCH); }
<INITIAL>"true" {
    yylval.bVal = true;
    LIST;
    printf("<bool:%s>\n", yytext);
    return BOOL_LITERAL;
}
<INITIAL>"while"                { token(WHILE); }

<INITIAL>"int"                  { token(INT); }
<INITIAL>"float"                { token(FLOAT); }
<INITIAL>"double"               { token(DOUBLE); }
<INITIAL>"void"                 { token(VOID); }
<INITIAL>"string"               { token(STRING); }

<INITIAL>"||"    { token(OR); }
<INITIAL>"&&"    { token(AND) ; }
<INITIAL>"!"     { token(NOT) ; }
<INITIAL>"<"     { token(LT) ; }
<INITIAL>"<="    { token(LE) ; }
<INITIAL>"=="    { token(EQ) ; }
<INITIAL>">="    { token(GE) ; }
<INITIAL>">"     { token(GT) ; }
<INITIAL>"!="    { token(NE) ; }
<INITIAL>"+"     { token(PLUS) ; }
<INITIAL>"-"     { token(MINUS) ; }
<INITIAL>"*"     { token(TIMES) ; }
<INITIAL>"/"     { token(DIVIDE) ; }
<INITIAL>"%"     { token(MOD) ; }
<INITIAL>"++"    { token(INC) ; }
<INITIAL>"--"    { token(DEC) ; }
<INITIAL>"="     { LIST; return(yytext[0]);  }
<INITIAL>".."    { token(RANGE); }

<INITIAL>{delimiter}        {LIST; return(yytext[0]);}
<INITIAL>[+-]?[0-9]+ { yylval.intVal = atoi(yytext); tokenInteger("int", yylval.intVal); }
<INITIAL>[+-]?[0-9]+\.[0-9]+([eE][+-]?[1-9][0-9]+)?       { yylval.floatVal = atof(yytext); tokenReal("REAL", yylval.floatVal); }
<INITIAL>[a-zA-Z][a-zA-Z0-9]*  { yylval.strVal = new string(yytext); printf("<%s:%s>\n","string",yytext); token(ID); }

<INITIAL>\"([^"]|\"\")*\" {
    char *start = yytext + 1;
    char *end = yytext + yyleng - 1;
    char *content = (char *)malloc(end - start + 1);
    char *p = start;
    char *q = content;
    while (p < end) {
        if (*p == '"' && *(p+1) == '"') {
            *q++ = '"';
            p += 2;
        } else {
            *q++ = *p++;
        }
    }
    *q = '\0';
    yylval.strVal = new string(yytext);
    tokenString("string", content);
    free(content);
}

<INITIAL>. { 
    LIST;
    printf("DEBUG: buf before error: %s\n", buf);
    printf("Error on line %d near text %s: bad character:'%s'\n", linenum, buf, yytext);
    exit(-1);
}
%%

void yyerror(const char *s);
