%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fstream>
#include <stack>
#include "symboltable.h"
using namespace std;

#define DEBUG 0
#define Trace(t) printf(t);

extern int yylex();
extern int linenum;
bool isMain = false;
extern FILE *yyin;

void yyerror(const char *s) {
    fprintf(stderr, "Error on line %d: %s\n", linenum, s);
}

// used for generating java byte code
ofstream out;
// used for local variable stack counter
int stack_number = 0;
// base for static variable name
string class_name;
int table_size = 0;
// layers for condition, loop
int last_index = -1;
stack<int> layers;

SymbolTable *current_table = new SymbolTable();
static int g_current_scalar_type; // Added for propagating scalar type
vector<Symbol*> *g_last_formal_parameters = nullptr;
static int g_current_function_return_type = _VOID; // Global for current function's expected return type, default to _VOID

string getT();
void generateConstantLoad(SymbolValue* value);

%}

/* Yacc Declarations */
%union {
    int intVal;
    float floatVal;
    string *strVal;
    bool bVal;
    int type;
    int dataType;
    SymbolValue *value;
    Symbol *symbol;

    Symbol *formal_parameter;
    vector<Symbol*> *formal_parameters;

    vector<SymbolValue*> *function_arguments; // for function call
}

%token <strVal> ID STRING_LITERAL
%token <intVal> INTEGER_LITERAL
%token <floatVal> REAL_LITERAL
%token <bVal> BOOL_LITERAL

%token BOOL CHAR INT FLOAT DOUBLE VOID STRING
%token CONST EXTERN
%token IF ELSE SWITCH CASE DEFAULT WHILE FOR FOREACH DO
%token BREAK CONTINUE RETURN
%token PRINT PRINTLN READ
%token TRUE FALSE

%token OR AND NOT LT LE EQ GE GT NE PLUS MINUS TIMES DIVIDE MOD INC DEC RANGE

%left OR
%left AND
%right NOT
%left LT LE EQ GE GT NE
%left PLUS MINUS
%left TIMES DIVIDE MOD
%right INC DEC
%nonassoc UMINUS

%type <value> expression constant_exp  identifier_decl simple_statement
%type <dataType>  scalar_type 
%type <function_arguments> function_arguments
%type <value> function_call
%type <formal_parameter> formal_parameter
%type <formal_parameters> formal_parameters
%type <intVal> array_dimensions


%start program

%% 

program:
    {
        out << "class " << class_name << endl << " {" << endl;
    }
    declarations function_declaration
    {
        Trace("Reducing to program\n");

        if (!isMain) {
            yyerror("No valid 'main' function found. Must define 'void main()'.");
        }

        dump_symbol_table(current_table);
        delete_symbol_table(current_table);
        out << "}" << endl;
    }

;

declarations:
    declarations declaration
    |
;

declaration:
    function_declaration
    | variable_declaration
    | constant_declaration
;

constant_declaration: CONST scalar_type ID '=' constant_exp ';'
                        {
                            Trace("Reducing to constant_declaration\n");
                            if (lookup_symbol(current_table, *$3, 0)) {
                                yyerror("Duplicate constant declaration");
                            }
                            else {
                                if ($2 != $5->dataType) {
                                    yyerror("constant declaration wrong type");
                                } else {
                                    Symbol *s = new Symbol(*$3, _VAR, 1);
                                    s->value = $5;
                                    insert_symbol(current_table, s);
                                }

                            }
                        }
                    ;

constant_exp: 
    INTEGER_LITERAL { 
        Trace("Reducing to constant_exp (INTEGER_LITERAL)\n");
        SymbolValue *d = new SymbolValue(_VAL, _INT, $1);
        $$ = d; }
    | REAL_LITERAL  { 
        Trace("Reducing to constant_exp (REAL_LITERAL)\n");
        SymbolValue *d = new SymbolValue(_VAL, _FLOAT, $1);
        $$ = d; }
    | STRING_LITERAL { 
        Trace("Reducing to constant_exp (STRING_LITERAL)\n");
        SymbolValue *d = new SymbolValue(_VAL, _STRING, $1);
        $$ = d; }
    | BOOL_LITERAL { 
        Trace("Reducing to constant_exp (BOOL_LITERAL)\n");
        SymbolValue *d = new SymbolValue(_VAL, _BOOL, $1);
        $$ = d; }
    ;
variable_declaration: scalar_type identifier_list ';' { Trace("Reducing to variable_declaration\n"); }
                ;

identifier_list: identifier_decl { Trace("Reducing to identifier_list (single_decl)\n"); /* Semantic action for identifier list */ }
            | identifier_list ',' identifier_decl { Trace("Reducing to identifier_list (recursive_decl)\n"); /* Semantic action for identifier list */ }
            ;

identifier_decl: ID {
                    Trace("Reducing to identifier_decl (ID)\n");
                    if (lookup_symbol(current_table, *$1, 0)) {
                        yyerror("variable exist");
                        $$ = nullptr; // Must assign to $$
                    } else {
                        Symbol *s = new Symbol(*$1, _VAR);
                        s->value = new SymbolValue(); // Create a value object
                        s->value->dataType = g_current_scalar_type; // Set its type

                        // Initialize with default value based on type
                        switch (g_current_scalar_type) {
                            case _INT: s->value->intVal = 0; break;
                            case _FLOAT: s->value->floatVal = 0.0f; break;
                            case _BOOL: s->value->bVal = false; break;
                            case _STRING: s->value->strVal = new string(""); break;
                            default: /* Handle error or unknown type, or leave as is if SymbolValue constructor handles defaults */
                                     // For safety, ensure all paths initialize relevant union member
                                     s->value->intVal = 0; // Default to int 0 if type is unhandled here
                                     break; 
                        }
                        insert_symbol(current_table, s);
                        $$ = s->value; // identifier_decl returns the initial value


                        // Code Generation for variable declaration
                        if( current_table->isGlobal() ) {
                            string type_str;
                            if (g_current_scalar_type == _BOOL) type_str = "int";
                            else if (g_current_scalar_type == _STRING) type_str = "java/lang/String";
                            else type_str = toDataTypeString(g_current_scalar_type);
                            out << "\tfield public static " << type_str << " " << *$1 << endl;
                        } else {
                            s->value->id = stack_number;
                            stack_number++;
                        }
                    }

                    
                }
            | ID '=' expression {
                    Trace("Reducing to identifier_decl (ID = expression)\n");
                    if (lookup_symbol(current_table, *$1, 0)) {
                        yyerror("variable exist");
                        $$ = nullptr; // Must assign to $$
                    } else {
                        if (!$3) {
                             yyerror("initializer expression is invalid");
                             $$ = nullptr;
                        } else if (g_current_scalar_type != $3->dataType) {
                            char err_msg[256];
                            // Using integers for type in error msg to be consistent with other error messages
                            sprintf(err_msg, "Type mismatch in initialization of '%s'. Expected type %d, got type %d.",
                                    (*$1).c_str(), g_current_scalar_type, $3->dataType);
                            yyerror(err_msg);
                            $$ = nullptr;
                        } else {
                            Symbol *s = new Symbol(*$1, _VAR);
                            s->value = $3; // $3 is from expression
                            insert_symbol(current_table, s);
                            $$ = s->value;

                            // Code Generation for variable initialization
                            if ( current_table->isGlobal() ) {
                                if ($3->type == _VAL) { // It's a constant expression
                                    string type_str;
                                    if (g_current_scalar_type == _BOOL) type_str = "int";
                                    else if (g_current_scalar_type == _STRING) type_str = "java/lang/String";
                                    else type_str = toDataTypeString(g_current_scalar_type);
                                    out << "\tfield public static " << type_str << " " << *$1 << " = ";
                                    if ($3->dataType == _BOOL) {
                                        out << ($3->bVal ? "1" : "0");
                                    } else if ($3->dataType == _INT) {
                                        out << std::to_string($3->intVal);
                                    } else if ($3->dataType == _FLOAT) {
                                        out << std::to_string($3->floatVal) << "F";
                                    } else if ($3->dataType == _STRING) {
                                        out << *$3->strVal;
                                    }
                                    out << endl;
                                } else {
                                    yyerror("Global variable initializers must be constant expressions.");
                                }
                            } else { // local variable
                                s->value->id = stack_number; // Assign stack_number for local variable
                                // Expression value is already on stack, so store it.
                                if ($3->dataType == _INT || $3->dataType == _BOOL) {
                                    out << getT() << "istore " << stack_number << endl;
                                } else if ($3->dataType == _FLOAT) {
                                    out << getT() << "fstore " << stack_number << endl;
                                } else if ($3->dataType == _STRING) {
                                    out << getT() << "astore " << stack_number << endl;
                                }
                                stack_number++;
                            }
                        }
                    }
                }
            | ID array_dimensions { // $2 is size from array_dimensions
                    Trace("Reducing to identifier_decl (ID array_dimensions)\n");
                    if (lookup_symbol(current_table, *$1, 0)) {
                        yyerror("variable exist");
                        $$ = nullptr; // Must assign to $$
                    } else {
                        Symbol *s = new Symbol(*$1, _ARRAY); // Set type to _ARRAY
                        s->size = $2; // Store size
                        s->value = new SymbolValue(); // Base value info for array type
                        s->value->dataType = g_current_scalar_type; // Store base data type

                        // Allocate and initialize the array storage
                        s->arr = new vector<SymbolValue*>();
                        s->arr->reserve($2); // Reserve space
                        for (int i = 0; i < $2; ++i) {
                            SymbolValue* elemVal = new SymbolValue();
                            elemVal->dataType = g_current_scalar_type;
                            // Initialize element based on type
                            switch (g_current_scalar_type) {
                                case _INT: elemVal->intVal = 0; break;
                                case _FLOAT: elemVal->floatVal = 0.0f; break;
                                case _BOOL: elemVal->bVal = false; break;
                                case _STRING: elemVal->strVal = new string(""); break;
                                default: elemVal->intVal = 0; break; // Default
                            }
                            s->arr->push_back(elemVal);
                        }

                        insert_symbol(current_table, s);
                        // Return nullptr for declaration itself
                        $$ = nullptr;
                    }
                }
            ;

array_dimensions: '[' INTEGER_LITERAL ']' { 
                    Trace("Reducing to array_dimensions (single)\n"); 
                    $$ = $2; // Return size
                 }
                // | array_dimensions '[' INTEGER_LITERAL ']' { /* Semantic action for array dimensions */ } // Multi-dim NYI
                ;

function_declaration: 
    scalar_type ID '(' formal_parameters ')' {
        Trace("Reducing to function_declaration (scalar_type)\n");
        g_current_function_return_type = $1; // Store expected return type globally
        if (lookup_symbol(current_table, *$2, 0)) {
            char err_msg[256];
            sprintf(err_msg, "Function/variable '%s' already declared in this scope", (*$2).c_str());
            yyerror(err_msg);
            // How to prevent block processing on error? For now, continue but symbol won't be inserted cleanly.
        } else {
            Symbol *s = new Symbol(*$2, _FUN);
            s->formal_parameters = $4;
            s->value = new SymbolValue(); // Assuming SymbolValue holds return type for functions
            s->value->dataType = $1;      // Store return type in symbol
            insert_symbol(current_table, s);
            table_size++;
        }
        g_last_formal_parameters = $4;

        // Code Generation for function header
        string ret_type_str;
        if ($1 == _BOOL) ret_type_str = "int";
        else if ($1 == _STRING) ret_type_str = "java/lang/String";
        else ret_type_str = toDataTypeString($1);
        out << getT() << "method public static " << ret_type_str << " " << *$2 << "(";
        for (size_t i = 0; i < $4->size(); i++) {
            if (i != 0) {
                out << ", ";
             }
            int param_type = $4->at(i)->value->dataType;
            string param_type_str;
            if (param_type == _BOOL) param_type_str = "int";
            else if (param_type == _STRING) param_type_str = "java/lang/String";
            else param_type_str = toDataTypeString(param_type);
            out << param_type_str;
        }
        out << ")" << endl;
        out << getT() << "max_stack 15" << endl << getT() << "max_locals 15" << endl;
        out << getT() << "{" << endl;
    }
    block
    {
        // Code Generation for function return
        if (g_current_function_return_type != _VOID) {
            out << getT() << "}" << endl; // Only return if not void
        }

        g_current_function_return_type = _VOID; // Reset after function block is parsed
    }
    | VOID ID '(' formal_parameters ')' {
        Trace("Reducing to function_declaration (VOID)\n");
        g_current_function_return_type = _VOID; // Store expected return type globally
        if (lookup_symbol(current_table, *$2, 0)) {
             char err_msg[256];
            sprintf(err_msg, "Function/variable '%s' already declared in this scope", (*$2).c_str());
            yyerror(err_msg);
        } else {
            if(*$2 == "main") isMain = true;
            Symbol *s = new Symbol(*$2, _FUN);
            s->formal_parameters = $4;
            s->value = new SymbolValue(); // Assuming SymbolValue holds return type
            s->value->dataType = _VOID; // Store return type _VOID in symbol
            insert_symbol(current_table, s);
            table_size++;
        }
        g_last_formal_parameters = $4;

        // Code Generation for function header
        out << getT() << "method public static void"  << " " << *$2 << "(";
        if (*$2 == "main" && $4->size() == 0) {
            out << "java.lang.String[]";
        } else {
            for (size_t i = 0; i < $4->size(); i++) {
                if (i != 0) {
                    out << ", ";
                }
                int param_type = $4->at(i)->value->dataType;
                string param_type_str;
                if (param_type == _BOOL) param_type_str = "int";
                else if (param_type == _STRING) param_type_str = "java/lang/String";
                else param_type_str = toDataTypeString(param_type);
                out << param_type_str;
            }
        }
        out << ")" << endl;
        out << getT() << "max_stack 15" << endl << getT() << "max_locals 15" << endl;
        out << getT() << "{" << endl;
    }
    block
    {
        g_current_function_return_type = _VOID; // Reset after function block is parsed
        
        // Code Generation for function return
        out << getT() << "return" << endl;
        out << getT() << "}" << endl; // Close function block
    }
;

block: '{' {
            SymbolTable *new_table = create_symbol_table(current_table);
            if (g_last_formal_parameters) {
                for (size_t i = 0; i < g_last_formal_parameters->size(); i++) {
                    auto master_param_sym = g_last_formal_parameters->at(i);
                    // Create a deep copy for the local scope using the new Symbol copy constructor
                    Symbol *local_scope_param_sym = new Symbol(*master_param_sym);
                    // Assign correct stack position for parameters (parameters start from 0)
                    if (local_scope_param_sym->value) {
                        local_scope_param_sym->value->id = i;
                    }
                    insert_symbol(new_table, local_scope_param_sym);
                }
                // Reset stack_number to start after parameters
                stack_number = g_last_formal_parameters->size();
                // g_last_formal_parameters = nullptr; // Moved reset after usage
            }
            current_table = new_table;
            g_last_formal_parameters = nullptr; // Reset g_last_formal_parameters after its use for this block
        }
        statements 
        '}' {
            Trace("Reducing to block\n");
            dump_symbol_table(current_table);
            SymbolTable *parent_table = current_table->parent;
            delete_symbol_table(current_table);
            current_table = parent_table;
    }
    ;

local_declaration: variable_declaration { Trace("Reducing to local_declaration (variable_declaration)\n"); /* Semantic action for local declaration */ }
                | constant_declaration { Trace("Reducing to local_declaration (constant_declaration)\n"); /* Semantic action for local declaration */ }
                ;

statements:
      /* empty */ { Trace("Reducing to statements (empty)\n"); }
    | statement statements { Trace("Reducing to statements (recursive)\n"); }
    ;

statement:
      simple_statement ';'
    | RETURN ';' { Trace("Reducing to statement (RETURN ;)\n"); }
    | conditional
    | loop
    | local_declaration { Trace("Reducing to statement (local_declaration)\n"); }
    ;

simple_statement:
                PRINT {
                    out << getT() << "getstatic java.io.PrintStream java.lang.System.out" << endl; 
                }
                expression {
                    Trace("Reducing to simple_statement (PRINT)\n"); 
                    out << getT() << "invokevirtual void java.io.PrintStream.print(";
                    if ($3->dataType == _STRING) {
                        out << "java.lang.String";
                    } else if ($3->dataType == _BOOL) {
                        out << "int";  // In Java bytecode, booleans are represented as int
                    } else {
                        out << toDataTypeString($3->dataType);
                    }
                    out << ")" << endl;
                    $$ = $3;
                    
                }
                | PRINTLN {
                    out << getT() << "getstatic java.io.PrintStream java.lang.System.out" << endl;
                }
                expression
                    { 
                        Trace("Reducing to simple_statement (PRINTLN)\n"); 
                        out << getT() << "invokevirtual void java.io.PrintStream.println(";
                        if ($3->dataType == _STRING) {
                            out << "java.lang.String";
                        } else if ($3->dataType == _BOOL) {
                            out << "int";  // In Java bytecode, booleans are represented as int
                        } else {
                            out << toDataTypeString($3->dataType);
                        }
                        out << ")" << endl;
                        $$ = $3;
                    }
                | READ ID
                    {
                        Trace("Reducing to simple_statement (READ)\n");
                        Symbol *sym = lookup_symbol(current_table, *$2, 1);
                        if (!sym) {
                            char err_msg[256];
                            sprintf(err_msg, "Undeclared variable '%s' in READ statement", (*$2).c_str());
                            yyerror(err_msg);
                        } else if (sym->is_const) {
                            char err_msg[256];
                            sprintf(err_msg, "Cannot read into const variable '%s'", (*$2).c_str());
                            yyerror(err_msg);
                        }
                        // TODO: Actual read logic to update sym->value
                        $$ = nullptr; // READ statement itself doesn't produce a value for expression stack
                    }
                | RETURN expression
                    { 
                        Trace("Reducing to simple_statement (RETURN expression)\\n"); 
                        $$ = $2; // Assume valid first, then check
                        if (g_current_function_return_type == _VOID) {
                             yyerror("Cannot return a value from a void function.");
                             $$ = nullptr; // Indicate error downstream if needed
                        } else if ($2 == nullptr) {
                             // This might happen if the expression itself had an error
                             yyerror("Returning an invalid or errorneous expression.");
                             $$ = nullptr;
                        } else if (g_current_function_return_type != $2->dataType) {
                             char err_msg[256];
                             // TODO: Use a function dataTypeToString(int type) for better messages
                             sprintf(err_msg, "Return type mismatch. Function expects type %d, but got type %d.", 
                                     g_current_function_return_type ,$2->dataType );
                             yyerror(err_msg);
                             $$ = nullptr; // Indicate error
                        } else {
                            // Generate correct return instruction based on type
                            switch($2->dataType) {
                                case _INT:
                                case _BOOL:
                                    out << getT() << "ireturn" << endl;
                                    break;
                                case _FLOAT:
                                    out << getT() << "freturn" << endl;
                                    break;
                                case _STRING:
                                    out << getT() << "areturn" << endl;
                                    break;
                                default:
                                    yyerror("Internal error: unsupported return type.");
                                    break;
                            }
                        }
                    }
                | ID '=' expression
                    {
                        Trace("Reducing to simple_statement (ID = expression)\n");
                        Symbol *sym = lookup_symbol(current_table, *$1, 1);
                        SymbolValue *result_val = nullptr;

                        if (!sym) {
                            char err_msg[256];
                            sprintf(err_msg, "Undeclared variable '%s' in assignment", (*$1).c_str());
                            yyerror(err_msg);
                        } else if (sym->is_const) {
                            char err_msg[256];
                            sprintf(err_msg, "Cannot assign to const variable '%s'", (*$1).c_str());
                            yyerror(err_msg);
                            result_val = sym->value;
                        } else if ($3 == nullptr) {
                            yyerror("Assigning a null/invalid expression result");
                        } else if (sym->value == nullptr) { // Should ideally not happen if var decl initializes sym->value
                            char err_msg[256];
                            sprintf(err_msg, "Variable '%s' not properly initialized before assignment", (*$1).c_str());
                            yyerror(err_msg);
                        } else if (sym->value->dataType != $3->dataType) {
                            char err_msg[256];
                            // Ideally, use a dataTypeToString function for better messages
                            sprintf(err_msg, "Type mismatch assigning to '%s'. Expected data type %d, got data type %d.",
                                    (*$1).c_str(), sym->value->dataType, $3->dataType);
                            yyerror(err_msg);
                            result_val = sym->value; // Keep old value on type error, or nullptr
                        } else {
                            // Types match
                            delete sym->value;
                            sym->value = new SymbolValue(*$3);
                            result_val = sym->value;
                        }
                        $$ = result_val;

                        //Code Generation for assignment
                        if (sym->is_global) {
                            // global var
                            int type = $3->dataType;
                            string type_str;
                            if (type == _BOOL) type_str = "int";
                            else if (type == _STRING) type_str = "java/lang/String";
                            else type_str = toDataTypeString(type);
                            out << getT() << "putstatic " << type_str << " " << class_name << "." << *$1 << endl;
                        } else {
                            //local var
                            switch(sym->value->dataType) {
                                case _INT:
                                case _BOOL:
                                    out << getT() << "istore " << std::to_string(sym->value->id) << endl;
                                    break;
                                case _FLOAT:
                                    out << getT() << "fstore " << std::to_string(sym->value->id) << endl;
                                    break;
                                case _STRING:
                                    out << getT() << "astore " << std::to_string(sym->value->id) << endl;
                                    break;
                                default:
                                    // Should not happen if type checking passed
                                    break;
                            }
                        }
                    }
                | ID '[' expression ']' '=' expression 
                    {
                        Trace("Reducing to simple_statement (ARRAY_ASSIGN)\n");
                        Symbol *sym = lookup_symbol(current_table, *$1, true);
                        SymbolValue *assign_val = $6; // Value from LHS expression ($6)
                        SymbolValue *target_element = nullptr; // Will point to the element to assign to

                        if (!sym) {
                            char err_msg[256]; sprintf(err_msg, "Undefined identifier '%s' used in array assignment", (*$1).c_str()); yyerror(err_msg);
                        } else if (sym->type != _ARRAY) {
                            char err_msg[256]; sprintf(err_msg, "Identifier '%s' is not an array", (*$1).c_str()); yyerror(err_msg);
                        } else if (!$3 || $3->dataType != _INT) {
                            yyerror("Array index must be an integer expression");
                        } else if (!sym->arr) {
                            char err_msg[256]; sprintf(err_msg, "Internal error: Array '%s' storage not initialized", (*$1).c_str()); yyerror(err_msg);
                        } else if (!$6) { // Check RHS value ($6)
                             yyerror("Assigning null/invalid expression result to array element");
                        } else {
                            int index = $3->intVal;
                            if (index < 0 || index >= sym->size) {
                                char err_msg[256]; sprintf(err_msg, "Array index %d out of range for '%s' (size %d) in assignment", index, (*$1).c_str(), sym->size); yyerror(err_msg);
                            } else {
                                target_element = sym->arr->at(index); // Get pointer to the existing element's SymbolValue
                                if (!target_element) { // Should not happen if array initialized correctly
                                   yyerror("Internal error: Array element pointer is null");
                                } else if (target_element->dataType != assign_val->dataType) { // Type check
                                   char err_msg[256]; sprintf(err_msg, "Type mismatch assigning to array '%s' element %d. Expected %d, got %d.", (*$1).c_str(), index, target_element->dataType, assign_val->dataType); yyerror(err_msg);
                                } else {
                                    // Perform the assignment by copying value (deep copy for string)
                                    switch (assign_val->dataType) {
                                        case _INT: target_element->intVal = assign_val->intVal; break;
                                        case _FLOAT: target_element->floatVal = assign_val->floatVal; break;
                                        case _BOOL: target_element->bVal = assign_val->bVal; break;
                                        case _STRING:
                                            // Ensure target has a string allocated if it doesn't
                                            if (!target_element->strVal) target_element->strVal = new string();
                                            *(target_element->strVal) = *(assign_val->strVal); // Copy string content
                                            break;
                                        // Add other types if needed
                                    }
                                }
                            }
                        }
                        // Return the assigned value, similar to regular assignment
                        $$ = $6; // Return RHS value ($6)
                    }
                | expression
                    {
                        Trace("Reducing to simple_statement (expression)\n");
                        if ($1) { // A void function call returns nullptr
                            out << getT() << "pop" << endl;
                        }
                        $$ = $1;
                    }
                ;

expression:
    expression PLUS expression {
                Trace("Reducing to expression (PLUS)\n");
                if ($1->dataType == _INT && $3->dataType == _INT) {
                    int n1, n2;
                    n1 = $1->intVal;
                    n2 = $3->intVal;
                    SymbolValue *d = new SymbolValue(_VAR, _INT, n1+n2);
                    $$ = d;

                    // Code Generation for addition
                    out << getT() << "iadd" << endl;

                } else if (($1->dataType == _INT || $1->dataType == _FLOAT) &&($3->dataType == _INT || $3->dataType == _FLOAT)) {
                    float n1, n2;
                    n1 = $1->floatVal;
                    n2 = $3->floatVal;
                    SymbolValue *d = new SymbolValue(_VAR, _FLOAT, n1+n2);
                    $$ = d;

                    // Code Generation for addition
                    out << getT() << "fadd" << endl;

                } else {
                    yyerror("add arithmetic with unsupported type");
                }
            }
    | expression MINUS expression {
                Trace("Reducing to expression (MINUS)\n");
                if ($1->dataType == _INT && $3->dataType == _INT) {
                    int n1, n2;
                    n1 = $1->intVal;
                    n2 = $3->intVal;
                    SymbolValue *d = new SymbolValue(_VAR, _INT, n1-n2);
                    $$ = d;

                    // Code Generation for addition
                    out << getT() << "isub" << endl;

                } else if (($1->dataType == _INT || $1->dataType == _FLOAT) &&($3->dataType == _INT || $3->dataType == _FLOAT)) {
                    float n1, n2;
                    n1 = $1->floatVal;
                    n2 = $3->floatVal;
                    SymbolValue *d = new SymbolValue(_VAR, _FLOAT, n1-n2);
                    $$ = d;

                    // Code Generation for addition
                    out << getT() << "fsub" << endl;

                } else {
                    yyerror("add arithmetic with unsupported type");
                }
            }
    | expression TIMES expression {
                Trace("Reducing to expression (TIMES)\n");
                if ($1->dataType == _INT && $3->dataType == _INT) {
                    int n1, n2;
                    n1 = $1->intVal;
                    n2 = $3->intVal;
                    SymbolValue *d = new SymbolValue(_VAR, _INT, n1*n2);
                    $$ = d;

                    // Code Generation for addition
                    out << getT() << "imul" << endl;

                } else if (($1->dataType == _INT || $1->dataType == _FLOAT) &&($3->dataType == _INT || $3->dataType == _FLOAT)) {
                    float n1, n2;
                    n1 = $1->floatVal;
                    n2 = $3->floatVal;
                    SymbolValue *d = new SymbolValue(_VAR, _FLOAT, n1*n2);
                    $$ = d;

                    // Code Generation for addition
                    out << getT() << "fmul" << endl;

                } else {
                    yyerror("add arithmetic with unsupported type");
                }
            }
    | expression DIVIDE expression {
                Trace("Reducing to expression (DIVIDE)\n");
                if ($1->dataType == _INT && $3->dataType == _INT) {
                    int n1, n2;
                    n1 = $1->intVal;
                    n2 = $3->intVal;
                    SymbolValue *d = new SymbolValue(_VAR, _INT, n1/n2);
                    $$ = d;

                    // Code Generation for addition
                    out << getT() << "idiv" << endl;

                } else if (($1->dataType == _INT || $1->dataType == _FLOAT) &&($3->dataType == _INT || $3->dataType == _FLOAT)) {
                    float n1, n2;
                    n1 = $1->floatVal;
                    n2 = $3->floatVal;
                    SymbolValue *d = new SymbolValue(_VAR, _FLOAT, n1/n2);
                    $$ = d;

                    // Code Generation for addition
                    out << getT() << "fdiv" << endl;

                } else {
                    yyerror("add arithmetic with unsupported type");
                }
            }
    | expression MOD expression {
                Trace("Reducing to expression (MOD)\n");
                if ($1->dataType == _INT && $3->dataType == _INT) {
                    int n1, n2;
                    n1 = $1->intVal;
                    n2 = $3->intVal;
                    SymbolValue *d = new SymbolValue(_VAR, _INT, n1%n2);
                    $$ = d;

                    // Code Generation for modulus
                    out << getT() << "irem" << endl;

                } else if (($1->dataType == _INT ) && ($3->dataType == _INT)) {
                    int n1, n2;
                    n1 = $1->intVal;
                    n2 = $3->intVal;
                    SymbolValue *d = new SymbolValue(_VAR, _FLOAT, n1%n2);
                    $$ = d;

                    // Code Generation for modulus
                    out << getT() << "frem" << endl;

                } else {
                    yyerror("add arithmetic with unsupported type");
                }
            }
    | MINUS expression %prec UMINUS {
        Trace("Reducing to expression (UMINUS)\n");
        SymbolValue *res = new SymbolValue();
        res->dataType = $2->dataType;
        if ($2->dataType == _INT) {
            res->intVal = -($2->intVal);
            // Code Generation for unary minus
            out << getT() << "ineg" << endl;
        }else if ($2->dataType == _FLOAT){
            res->floatVal = -($2->floatVal);
            // Code Generation for unary minus
            out << getT() << "fneg" << endl;
        }
        else yyerror("type error");
        $$ = res;
    }    
    | ID INC {
        Trace("Reducing to expression (ID INC)\n");
        Symbol *sym = lookup_symbol(current_table, *$1, 1);
        if (!sym) {
            char err_msg[256];
            sprintf(err_msg, "Variable '%s' not defined", (*$1).c_str());
            yyerror(err_msg);
            SymbolValue *errVal = new SymbolValue(); errVal->dataType = _INT; errVal->intVal = 0;
            $$ = errVal;
        } else if (sym->is_const) {
             yyerror("Cannot increment a constant variable.");
             $$ = sym->value;
        }
        else {
                         if (sym->value->dataType == _INT) {
                 // Post-increment: leave old value on stack, then increment variable.
                 // 1. Load current value of variable onto stack (for return value).
                 if (sym->is_global) {
                     out << getT() << "getstatic int " << class_name << "." << *$1 << endl;
                 } else {
                     out << getT() << "iload " << sym->value->id << endl;
                 }
                 
                 // 2. Increment variable in memory.
                 if (sym->is_global) {
                     out << getT() << "getstatic int " << class_name << "." << *$1 << endl;
                     out << getT() << "iconst_1" << endl;
                     out << getT() << "iadd" << endl;
                     out << getT() << "putstatic int " << class_name << "." << *$1 << endl;
                 } else {
                     // Use iadd instead of iinc for local variables
                     out << getT() << "iload " << sym->value->id << endl;
                     out << getT() << "iconst_1" << endl;
                     out << getT() << "iadd" << endl;
                     out << getT() << "istore " << sym->value->id << endl;
                 }
                 
                 // Create a new SymbolValue for the expression result (the value before increment)
                 SymbolValue *res = new SymbolValue(*sym->value);
                 // The C++ side must also see the increment.
                 sym->value->intVal++; 
                 $$ = res;

            } else if (sym->value->dataType == _FLOAT) {
                // Post-increment for float
                // 1. Load
                if (sym->is_global) {
                    out << getT() << "getstatic float " << class_name << "." << *$1 << endl;
                } else {
                    out << getT() << "fload " << sym->value->id << endl;
                }
                
                // 2. Increment
                if (sym->is_global) {
                    out << getT() << "getstatic float " << class_name << "." << *$1 << endl;
                    out << getT() << "fconst_1" << endl;
                    out << getT() << "fadd" << endl;
                    out << getT() << "putstatic float " << class_name << "." << *$1 << endl;
                } else {
                    out << getT() << "fload " << sym->value->id << endl;
                    out << getT() << "fconst_1" << endl;
                    out << getT() << "fadd" << endl;
                    out << getT() << "fstore " << sym->value->id << endl;
                }
                
                SymbolValue *res = new SymbolValue(*sym->value);
                sym->value->floatVal++;
                $$ = res;

            } else {
                yyerror("wrong dataType for INC");
                $$ = sym->value;
            }
        }
    }
    | ID DEC {
        // similar logic for decrement
        Trace("Reducing to expression (ID DEC)\n");
        Symbol *sym = lookup_symbol(current_table, *$1, 1);
        if (!sym) {
            char err_msg[256];
            sprintf(err_msg, "Variable '%s' not defined", (*$1).c_str());
            yyerror(err_msg);
            SymbolValue *errVal = new SymbolValue(); errVal->dataType = _INT; errVal->intVal = 0;
            $$ = errVal;
        } else if (sym->is_const) {
             yyerror("Cannot decrement a constant variable.");
             $$ = sym->value;
        } else {
                         if (sym->value->dataType == _INT) {
                 // Post-decrement: leave old value on stack, then decrement variable.
                 // 1. Load current value of variable onto stack (for return value).
                 if (sym->is_global) {
                     out << getT() << "getstatic int " << class_name << "." << *$1 << endl;
                 } else {
                     out << getT() << "iload " << sym->value->id << endl;
                 }
                 
                 // 2. Decrement variable in memory.
                 if (sym->is_global) {
                     out << getT() << "getstatic int " << class_name << "." << *$1 << endl;
                     out << getT() << "iconst_1" << endl;
                     out << getT() << "isub" << endl;
                     out << getT() << "putstatic int " << class_name << "." << *$1 << endl;
                 } else {
                     // Use isub instead of iinc for local variables
                     out << getT() << "iload " << sym->value->id << endl;
                     out << getT() << "iconst_1" << endl;
                     out << getT() << "isub" << endl;
                     out << getT() << "istore " << sym->value->id << endl;
                 }
                 SymbolValue *res = new SymbolValue(*sym->value);
                 sym->value->intVal--; 
                 $$ = res;

            } else if (sym->value->dataType == _FLOAT) {
                if (sym->is_global) {
                    out << getT() << "getstatic float " << class_name << "." << *$1 << endl;
                } else {
                    out << getT() << "fload " << sym->value->id << endl;
                }
                if (sym->is_global) {
                    out << getT() << "getstatic float " << class_name << "." << *$1 << endl;
                    out << getT() << "fconst_1" << endl;
                    out << getT() << "fsub" << endl;
                    out << getT() << "putstatic float " << class_name << "." << *$1 << endl;
                } else {
                    out << getT() << "fload " << sym->value->id << endl;
                    out << getT() << "fconst_1" << endl;
                    out << getT() << "fsub" << endl;
                    out << getT() << "fstore " << sym->value->id << endl;
                }
                SymbolValue *res = new SymbolValue(*sym->value);
                sym->value->floatVal--;
                $$ = res;

            } else {
                yyerror("wrong dataType for DEC");
                $$ = sym->value;
            }
        }
    }
    | '(' expression ')' { Trace("Reducing to expression (parentheses)\n"); $$ = $2; }
    | ID {
        Trace("Reducing to expression (ID)\n");
        Symbol *sym = lookup_symbol(current_table, *$1, true);
        if (!sym) {
            char err_msg[256];
            sprintf(err_msg, "Variable '%s' not defined", (*$1).c_str());
            yyerror(err_msg);
            // Return a dummy value to prevent crash if yyerror doesn't halt parsing.
            // Ensure this dummy value is consistent with %type <value> (SymbolValue*).
            SymbolValue *errVal = new SymbolValue(); 
            errVal->dataType = _INT; // Or some _ERROR type if you have one
            errVal->intVal = 0;
            $$ = errVal;
        } else {
           if (!sym->value) {
               // This case should be less likely if declarations properly initialize sym->value.
               char err_msg[256];
               sprintf(err_msg, "Variable '%s' used before initialization", (*$1).c_str());
               yyerror(err_msg);
               SymbolValue *errVal = new SymbolValue();
               errVal->dataType = sym->value ? sym->value->dataType : _INT; // Try to use declared type, else default
               // Initialize based on type to avoid garbage
               if (errVal->dataType == _INT) errVal->intVal = 0;
               else if (errVal->dataType == _FLOAT) errVal->floatVal = 0.0f;
               // Add other types as needed
               else errVal->intVal = 0; // fallback
               $$ = errVal;
           } else {
               $$ = sym->value;
           }
        }

        // Code Generation for variable/constant access
        if (sym && sym->is_const) {
            generateConstantLoad(sym->value);
        } else if (sym) {
            if (sym->is_global) {
                // global var
                int type = sym->value->dataType;
                string type_str;
                if (type == _BOOL) type_str = "int";
                else if (type == _STRING) type_str = "java/lang/String";
                else type_str = toDataTypeString(type);
                out << getT() << "getstatic " << type_str << " "
                << class_name << "." << *$1 << endl;
            } else {
                // local var
                if (sym->value->dataType == _INT || sym->value->dataType == _BOOL) {
                    out << getT() << "iload " << sym->value->id << endl;
                } else if (sym->value->dataType == _FLOAT) {
                    out << getT() << "fload " << sym->value->id << endl;
                } else if (sym->value->dataType == _STRING) {
                    out << getT() << "aload " << sym->value->id << endl;
                }
            }
        }
    }
    | ID '[' expression ']' {
        Trace("Reducing to expression (array_access)\n");
        Symbol *sym = lookup_symbol(current_table, *$1, true);
        SymbolValue *result_val = nullptr; // Default return value on error

        if (sym == NULL) {
            char err_msg[256];
            sprintf(err_msg, "Undefined identifier '%s' used in array access", (*$1).c_str());
            yyerror(err_msg);
        } else if (sym->type != _ARRAY) { // Check if it's actually an array
             char err_msg[256];
             sprintf(err_msg, "Identifier '%s' is not an array", (*$1).c_str());
             yyerror(err_msg);
        } else if ($3 == nullptr || $3->dataType != _INT) { // Check index is INT
            yyerror("Array index must be an integer expression");
        } else if (!sym->arr) { // Check if array vector exists
             char err_msg[256];
             sprintf(err_msg, "Internal error: Array '%s' storage not initialized", (*$1).c_str());
             yyerror(err_msg);
        } else {
            int index = $3->intVal;
            if (index < 0 || index >= sym->size) { // Bounds check
                char err_msg[256];
                sprintf(err_msg, "Array index %d out of range for '%s' (size %d)", index, (*$1).c_str(), sym->size);
                yyerror(err_msg);
            } else {
                // Access is valid, return pointer to the element's SymbolValue
                result_val = sym->arr->at(index);
            }
        }

        // If result_val is still nullptr due to error, create a dummy value to avoid crashes downstream
        if (!result_val) {
             result_val = new SymbolValue();
             // Try to determine the intended type, default to INT
             int defaultType = _INT;
             if(sym && sym->value) { // Use the array's base type if possible
                defaultType = sym->value->dataType;
             }
             result_val->dataType = defaultType;

             // Initialize based on type
             switch(defaultType) {
                case _INT: result_val->intVal = 0; break;
                case _FLOAT: result_val->floatVal = 0.0f; break;
                case _BOOL: result_val->bVal = false; break;
                case _STRING: result_val->strVal = new string(""); break;
                default: result_val->intVal = 0; break; // Fallback
             }
        }
        $$ = result_val;
    }
    | function_call { Trace("Reducing to expression (function_call)\n"); $$ = $1; }
    | constant_exp { 
        Trace("Reducing to expression (constant_exp)\\n"); 
        if (!current_table->isGlobal()) {
            generateConstantLoad($1);
        }
        $$ = $1; 
    }
    | expression AND expression {
        Trace("Reducing to expression (AND)\n");
        if ($1->dataType == _BOOL && $3->dataType == _BOOL) {
            bool n1, n2;
            n1 = $1->bVal;
            n2 = $3->bVal;
            SymbolValue *d = new SymbolValue(_VAR, _BOOL, n1 && n2);
            $$ = d;

            // Code Generation for AND
            out << getT() << "iand" << endl;

        } else {
            yyerror("Logical AND operation requires boolean types.");
        }
    }
    | expression OR expression {
        Trace("Reducing to expression (OR)\n");
        if ($1->dataType == _BOOL && $3->dataType == _BOOL) {
            bool n1, n2;
            n1 = $1->bVal;
            n2 = $3->bVal;
            SymbolValue *d = new SymbolValue(_VAR, _BOOL, n1 || n2);
            $$ = d;

            // Code Generation for OR
            out << getT() << "ior" << endl;

        } else {
            yyerror("Logical OR operation requires boolean types.");
        }
    }
    | NOT expression {
        Trace("Reducing to expression (NOT)\n");
        if ($2->dataType == _BOOL) {
            bool n1 = $2->bVal;
            SymbolValue *d = new SymbolValue(_VAR, _BOOL, !n1);
            $$ = d;

            // Code Generation for NOT
            out << getT() << "ldc 1" << endl;
            out << getT() << "ixor" << endl;

        } else {
            yyerror("Logical NOT operation requires a boolean type.");
        }
    }
    | expression LT expression {
        Trace("Reducing to LT\\n");
        if ($1->dataType == _STRING || $3->dataType == _STRING) {
            yyerror("Relational comparison (LT) not supported for string types.");
        } else if ($1->dataType == _BOOL && $3->dataType == _BOOL) {
            yyerror("Relational comparison (LT) not supported for boolean types.");
        } else if (($1->dataType == _INT || $1->dataType == _FLOAT) && 
                   ($3->dataType == _INT || $3->dataType == _FLOAT)) {
            float v1 = ($1->dataType == _INT) ? (float)$1->intVal : $1->floatVal;
            float v2 = ($3->dataType == _INT) ? (float)$3->intVal : $3->floatVal;
            bool b = v1 < v2;
            SymbolValue *res = new SymbolValue(_VAL, _BOOL, b); 
            $$ = res;

            // Code Generation for LT
            layers.push(++last_index);
            if ($1->dataType == _FLOAT || $3->dataType == _FLOAT) {
                out << getT() << "fcmpl" << endl;
            } else {
                out << getT() << "isub" << endl;
            }
            out << getT() << "iflt L_" << layers.top() << "_true" << endl;
            out << getT() << "iconst_0" << endl;
            out << getT() << "goto L_" << layers.top() << "_end" << endl;
            out << "L_" << layers.top() << "_true:" << endl;
            out << getT() << "iconst_1" << endl;
            out << "L_" << layers.top() << "_end:" << endl;
            layers.pop();
        } else {
            yyerror("Type mismatch for LT operator. Operands must be numeric or boolean.");
        }
    }
    | expression LE expression {
        Trace("Reducing to LE\\n");
        if ($1->dataType == _STRING || $3->dataType == _STRING) {
            yyerror("Relational comparison (LE) not supported for string types.");
        } else if ($1->dataType == _BOOL && $3->dataType == _BOOL) {
            yyerror("Relational comparison (LE) not supported for boolean types.");
        } else if (($1->dataType == _INT || $1->dataType == _FLOAT) && 
                ($3->dataType == _INT || $3->dataType == _FLOAT)) {
            float v1 = ($1->dataType == _INT) ? (float)$1->intVal : $1->floatVal;
            float v2 = ($3->dataType == _INT) ? (float)$3->intVal : $3->floatVal;
            bool b = v1 <= v2;
            SymbolValue *res = new SymbolValue(_VAL, _BOOL, b); 
            $$ = res;

            // Code Generation for LE
            layers.push(++last_index);
            if ($1->dataType == _FLOAT || $3->dataType == _FLOAT) {
                out << getT() << "fcmpl" << endl;
            } else {
                out << getT() << "isub" << endl;
            }
            out << getT() << "ifle L_" << layers.top() << "_true" << endl;
            out << getT() << "iconst_0" << endl;
            out << getT() << "goto L_" << layers.top() << "_end" << endl;
            out << "L_" << layers.top() << "_true:" << endl;
            out << getT() << "iconst_1" << endl;
            out << "L_" << layers.top() << "_end:" << endl;
            layers.pop();
        } else {
            yyerror("Type mismatch for LE operator. Operands must be numeric or boolean.");
        }
    }
    | expression EQ expression {
        Trace("Reducing to EQ\\n");
        if ($1->dataType == _STRING || $3->dataType == _STRING) {
            yyerror("Relational comparison (EQ) not supported for string types.");
        } else if ($1->dataType == _BOOL && $3->dataType == _BOOL) {
            bool b = ($1->bVal == $3->bVal);
            SymbolValue *res = new SymbolValue(_VAL, _BOOL, b); 
            $$ = res;

            // Code Generation for EQ on bool
            layers.push(++last_index);
            out << getT() << "isub" << endl;
            out << getT() << "ifeq L_" << layers.top() << "_true" << endl;
            out << getT() << "iconst_0" << endl;
            out << getT() << "goto L_" << layers.top() << "_end" << endl;
            out << "L_" << layers.top() << "_true:" << endl;
            out << getT() << "iconst_1" << endl;
            out << "L_" << layers.top() << "_end:" << endl;
            layers.pop();
        } else if (($1->dataType == _INT || $1->dataType == _FLOAT) && 
                   ($3->dataType == _INT || $3->dataType == _FLOAT)) {
            float v1 = ($1->dataType == _INT) ? (float)$1->intVal : $1->floatVal;
            float v2 = ($3->dataType == _INT) ? (float)$3->intVal : $3->floatVal;
            bool b = (v1 == v2);
            SymbolValue *res = new SymbolValue(_VAL, _BOOL, b); 
            $$ = res;

            // Code Generation for EQ
            layers.push(++last_index);
            if ($1->dataType == _FLOAT || $3->dataType == _FLOAT) {
                out << getT() << "fcmpl" << endl;
            } else {
                out << getT() << "isub" << endl;
            }
            out << getT() << "ifeq L_" << layers.top() << "_true" << endl;
            out << getT() << "iconst_0" << endl;
            out << getT() << "goto L_" << layers.top() << "_end" << endl;
            out << "L_" << layers.top() << "_true:" << endl;
            out << getT() << "iconst_1" << endl;
            out << "L_" << layers.top() << "_end:" << endl;
            layers.pop();
        } else {
            yyerror("Type mismatch for EQ operator. Operands must be numeric or boolean.");
        }
    }
    | expression GE expression {
        Trace("Reducing to GE\\n");
        if ($1->dataType == _STRING || $3->dataType == _STRING) {
            yyerror("Relational comparison (GE) not supported for string types.");
        } else if ($1->dataType == _BOOL && $3->dataType == _BOOL) {
            yyerror("Relational comparison (GE) not supported for boolean types.");
        } else if (($1->dataType == _INT || $1->dataType == _FLOAT) && 
                ($3->dataType == _INT || $3->dataType == _FLOAT)) {
            float v1 = ($1->dataType == _INT) ? (float)$1->intVal : $1->floatVal;
            float v2 = ($3->dataType == _INT) ? (float)$3->intVal : $3->floatVal;
            bool b = v1 >= v2;
            SymbolValue *res = new SymbolValue(_VAL, _BOOL, b); 
            $$ = res;

            // Code Generation for GE
            layers.push(++last_index);
            if ($1->dataType == _FLOAT || $3->dataType == _FLOAT) {
                out << getT() << "fcmpg" << endl;
            } else {
                out << getT() << "isub" << endl;
            }
            out << getT() << "ifge L_" << layers.top() << "_true" << endl;
            out << getT() << "iconst_0" << endl;
            out << getT() << "goto L_" << layers.top() << "_end" << endl;
            out << "L_" << layers.top() << "_true:" << endl;
            out << getT() << "iconst_1" << endl;
            out << "L_" << layers.top() << "_end:" << endl;
            layers.pop();
        } else {
            yyerror("Type mismatch for GE operator. Operands must be numeric or boolean.");
        }        
    }
    | expression GT expression {
        Trace("Reducing to GT\\n");
        if ($1->dataType == _STRING || $3->dataType == _STRING) {
            yyerror("Relational comparison (GT) not supported for string types.");
        } else if ($1->dataType == _BOOL && $3->dataType == _BOOL) {
            yyerror("Relational comparison (GT) not supported for boolean types.");
        } else if (($1->dataType == _INT || $1->dataType == _FLOAT) && 
                ($3->dataType == _INT || $3->dataType == _FLOAT)) {
            float v1 = ($1->dataType == _INT) ? (float)$1->intVal : $1->floatVal;
            float v2 = ($3->dataType == _INT) ? (float)$3->intVal : $3->floatVal;
            bool b = v1 > v2;
            SymbolValue *res = new SymbolValue(_VAL, _BOOL, b); 
            $$ = res;

            // Code Generation for GT
            layers.push(++last_index);
            if ($1->dataType == _FLOAT || $3->dataType == _FLOAT) {
                out << getT() << "fcmpg" << endl;
            } else {
                out << getT() << "isub" << endl;
            }
            out << getT() << "ifgt L_" << layers.top() << "_true" << endl;
            out << getT() << "iconst_0" << endl;
            out << getT() << "goto L_" << layers.top() << "_end" << endl;
            out << "L_" << layers.top() << "_true:" << endl;
            out << getT() << "iconst_1" << endl;
            out << "L_" << layers.top() << "_end:" << endl;
            layers.pop();
        } else {
            yyerror("Type mismatch for GT operator. Operands must be numeric or boolean.");
        }
    }
    | expression NE expression {
        Trace("Reducing to NE\\n");
        if ($1->dataType == _STRING || $3->dataType == _STRING) {
            yyerror("Relational comparison (NE) not supported for string types.");
        } else if ($1->dataType == _BOOL && $3->dataType == _BOOL) {
            bool b = ($1->bVal != $3->bVal);
            SymbolValue *res = new SymbolValue(_VAL, _BOOL, b); 
            $$ = res;

            // Code Generation for NE on bool
            layers.push(++last_index);
            out << getT() << "isub" << endl;
            out << getT() << "ifne L_" << layers.top() << "_true" << endl;
            out << getT() << "iconst_0" << endl;
            out << getT() << "goto L_" << layers.top() << "_end" << endl;
            out << "L_" << layers.top() << "_true:" << endl;
            out << getT() << "iconst_1" << endl;
            out << "L_" << layers.top() << "_end:" << endl;
            layers.pop();
        } else if (($1->dataType == _INT || $1->dataType == _FLOAT) && 
                ($3->dataType == _INT || $3->dataType == _FLOAT)) {
            float v1 = ($1->dataType == _INT) ? (float)$1->intVal : $1->floatVal;
            float v2 = ($3->dataType == _INT) ? (float)$3->intVal : $3->floatVal;
            bool b = v1 != v2;
            SymbolValue *res = new SymbolValue(_VAL, _BOOL, b); 
            $$ = res;

            // Code Generation for NE
            layers.push(++last_index);
            if ($1->dataType == _FLOAT || $3->dataType == _FLOAT) {
                out << getT() << "fcmpl" << endl;
            } else {
                out << getT() << "isub" << endl;
            }
            out << getT() << "ifne L_" << layers.top() << "_true" << endl;
            out << getT() << "iconst_0" << endl;
            out << getT() << "goto L_" << layers.top() << "_end" << endl;
            out << "L_" << layers.top() << "_true:" << endl;
            out << getT() << "iconst_1" << endl;
            out << "L_" << layers.top() << "_end:" << endl;
            layers.pop();
        } else {
            yyerror("Type mismatch for NE operator. Operands must be numeric or boolean.");
        }       
    }
;


function_call:
    ID '(' function_arguments ')'
    {
        Trace("Reducing to function_call\n");
        Symbol *func = lookup_symbol(current_table, *$1, 1);
        SymbolValue *result_val = nullptr; // Default return value

        if (!func) {
            char err_msg[256]; sprintf(err_msg, "Function '%s' not defined", (*$1).c_str()); yyerror(err_msg);
            result_val = new SymbolValue(_VAL, _INT, 0);
        } else if (func->type != _FUN) {
            char err_msg[256]; sprintf(err_msg, "'%s' is not a function", (*$1).c_str()); yyerror(err_msg);
            result_val = new SymbolValue(_VAL, _INT, 0);
        } else if (!func->formal_parameters) {
            char err_msg[256]; sprintf(err_msg, "Internal error: Function '%s' formal parameters are null", (*$1).c_str()); yyerror(err_msg);
            result_val = new SymbolValue(_VAL, _INT, 0);
        } else if (func->formal_parameters->size() != $3->size()) {
            char err_msg[256]; sprintf(err_msg, "Function '%s' argument count mismatch. Expected %zu, got %zu.",
                                     (*$1).c_str(), func->formal_parameters->size(), $3->size());
            yyerror(err_msg);
            result_val = new SymbolValue(_VAL, _INT, 0);
        } else {
            bool type_mismatch = false;
            for (size_t i = 0; i < $3->size(); ++i) {
                if (!func->formal_parameters->at(i) || !func->formal_parameters->at(i)->value || !$3->at(i)) {
                    char err_msg[256]; sprintf(err_msg, "Internal error checking types for function '%s' argument %zu.", (*$1).c_str(), i+1); yyerror(err_msg);
                    type_mismatch = true; break;
                }
                if (func->formal_parameters->at(i)->value->dataType != $3->at(i)->dataType) {
                    char err_msg[256]; sprintf(err_msg, "Type mismatch for argument %zu in function '%s'. Expected type %d, got type %d.",
                        i + 1, (*$1).c_str(), func->formal_parameters->at(i)->value->dataType, $3->at(i)->dataType);
                    yyerror(err_msg);
                    type_mismatch = true;
                    break;
                }
            }
            if (!type_mismatch) {
                // --- Java assembly code generation for function call ---
                // Arguments are already pushed by evaluating expressions in $3
                out << getT() << "invokestatic ";
                if (func->value->dataType == _VOID) {
                    out << "void ";
                } else {
                    int ret_type = func->value->dataType;
                    string ret_type_str;
                    if (ret_type == _BOOL) ret_type_str = "int";
                    else if (ret_type == _STRING) ret_type_str = "java/lang/String";
                    else ret_type_str = toDataTypeString(ret_type);
                    out << ret_type_str << " ";
                }
                out << class_name << "." << *$1 << "(";
                for (size_t i = 0; i < func->formal_parameters->size(); ++i) {
                    if (i != 0) out << ", ";
                    int param_type = func->formal_parameters->at(i)->value->dataType;
                    string param_type_str;
                    if (param_type == _BOOL) param_type_str = "int";
                    else if (param_type == _STRING) param_type_str = "java/lang/String";
                    else param_type_str = toDataTypeString(param_type);
                    out << param_type_str;
                }
                out << ")" << endl;
                // ------------------------------------------------------

                result_val = callFunction(func, $3);
                if (!result_val && func->value->dataType != _VOID) {
                    // If function wasn't VOID but call returned null, something might be wrong in callFunction
                }
                if (func->value->dataType == _VOID) {
                    result_val = nullptr;
                }
            } else {
                result_val = new SymbolValue(_VAL, _INT, 0);
            }
        }
        $$ = result_val;
    }
;


conditional:
    IF expression
    {
        // $2 is the SymbolValue* from expression
        if ($2 == nullptr || !($2->dataType == _BOOL)) { 
            yyerror("Conditional expression must be of boolean type");
        }
        layers.push(++last_index);
        // if expression is true (1), (1==0) is false, no jump.
        // if expression is false (0), (0==0) is true, jump to L_idx_false.
        out << getT() << "ifeq L_" << std::to_string(layers.top()) << "_false" << endl;
    }
    condition_body  // True block
    condition_else
    ;

condition_else:
    ELSE
    {
        Trace("Reducing to conditional (IF-ELSE)\n"); // Original trace message
        out << getT() << "goto L_" << std::to_string(layers.top()) << "_end" << endl;
        out << "L_" << std::to_string(layers.top()) << "_false:" << endl;
    }
    condition_body  // False block
    {
        out << "L_" << std::to_string(layers.top()) << "_end:" << endl;
        out << getT() << "nop" << endl;
        layers.pop();
    }
    | /* Epsilon rule for IF without ELSE */
    {
        Trace("Reducing to conditional (IF)\n"); // Original trace message
        // If condition was false, execution jumps to L_idx_false.
        out << "L_" << std::to_string(layers.top()) << "_false:" << endl;
        out << getT() << "nop" << endl;
        layers.pop();
    }
    ;

condition_body: statement
    | block
    ;

loop:
    WHILE{
        layers.push(++last_index);
        out << "L_" << layers.top() << "_begin:" << endl;
    } 
    '(' expression ')'{
        Trace("Reducing to loop (WHILE)\n");
        if( $4->dataType != _BOOL){
            yyerror("Conditional expression must be of boolean type");
        }
        // The boolean expression evaluation leaves 0 or 1 on stack
        // If it's 0 (false), jump to end
        out << getT() << "ifeq L_" << layers.top() << "_exit" << endl;
    }
    condition_body
    {
        // goto beginning of the loop
        out << getT() << "goto L_" << layers.top() << "_begin" << endl;
        // end entry of loop
        out << "L_" << layers.top() << "_exit:" << endl;
        out << getT() << "nop" << endl;
        layers.pop();
    }
    |
    FOR '(' simple_statement ';' {
        // Initialize the for loop - push layer and setup labels
        layers.push(++last_index);
        // The initialization statement has been executed
        // Now start the loop with condition check
        out << "L_" << layers.top() << "_begin:" << endl;
    }
    expression ';' {
        // Check condition
        if ($6->dataType != _BOOL) {
            yyerror("FOR loop condition must be boolean");
        }
        // If condition is false, jump to end
        out << getT() << "ifeq L_" << layers.top() << "_exit" << endl;
        // If condition is true, jump to body
        out << getT() << "goto L_" << layers.top() << "_body" << endl;
        // Label for increment section
        out << "L_" << layers.top() << "_increment:" << endl;
    }
    simple_statement ')' {
        // The increment statement execution happens here
        // After increment, go back to condition check
        out << getT() << "goto L_" << layers.top() << "_begin" << endl;
        // Label for loop body
        out << "L_" << layers.top() << "_body:" << endl;
    }
    condition_body
    {
        Trace("Reducing to loop (FOR)\n");
        // After body, jump to increment section
        out << getT() << "goto L_" << layers.top() << "_increment" << endl;
        // End of loop
        out << "L_" << layers.top() << "_exit:" << endl;
        out << getT() << "nop" << endl;
        layers.pop();
    }
    |
    FOREACH '(' ID ':' expression RANGE expression ')' {
        // Initialize FOREACH loop
        layers.push(++last_index);
        Symbol *loop_var = lookup_symbol(current_table, *$3, 1);
        if (!loop_var) {
            yyerror("FOREACH loop variable not declared");
        } else {
            // Set loop variable to start value ($5)
            // First, generate code to load the start value onto the stack
            generateConstantLoad($5);
            
            if (loop_var->is_global) {
                out << getT() << "putstatic int " << class_name << "." << *$3 << endl;
            } else {
                out << getT() << "istore " << loop_var->value->id << endl;
            }
        }
        
        // Determine if it's ascending or descending by comparing start and end values
        // At compile time, we can determine the direction
        bool is_ascending = true;
        if ($5->dataType == _INT && $7->dataType == _INT) {
            is_ascending = ($5->intVal <= $7->intVal);
        }
        
        if (is_ascending) {
            // Ascending case: start <= end
            out << "L_" << layers.top() << "_begin:" << endl;
            
            // Load loop variable and end value for comparison
            if (loop_var && loop_var->is_global) {
                out << getT() << "getstatic int " << class_name << "." << *$3 << endl;
            } else if (loop_var) {
                out << getT() << "iload " << loop_var->value->id << endl;
            }
            if ($7->dataType == _INT) {
                out << getT() << "sipush " << $7->intVal << endl;
            }
            // Compare: if loop_var > end_value, exit loop (while i <= end)
            out << getT() << "isub" << endl;
            out << getT() << "ifgt L_" << layers.top() << "_exit" << endl;
        } else {
            // Descending case: start > end
            out << "L_" << layers.top() << "_begin:" << endl;
            
            // Load loop variable and end value for comparison
            if (loop_var && loop_var->is_global) {
                out << getT() << "getstatic int " << class_name << "." << *$3 << endl;
            } else if (loop_var) {
                out << getT() << "iload " << loop_var->value->id << endl;
            }
            if ($7->dataType == _INT) {
                out << getT() << "sipush " << $7->intVal << endl;
            }
            // Compare: if loop_var < end_value, exit loop (while i >= end)
            out << getT() << "isub" << endl;
            out << getT() << "iflt L_" << layers.top() << "_exit" << endl;
        }
    }
    condition_body
    {
        Symbol *loop_var = lookup_symbol(current_table, *$3, 1);
        
        // Determine direction again (this should match the earlier determination)
        bool is_ascending = true;
        if ($5->dataType == _INT && $7->dataType == _INT) {
            is_ascending = ($5->intVal <= $7->intVal);
        }
        
        if (is_ascending) {
            // Ascending increment
            if (loop_var && loop_var->is_global) {
                out << getT() << "getstatic int " << class_name << "." << *$3 << endl;
                out << getT() << "iconst_1" << endl;
                out << getT() << "iadd" << endl;  // Add 1 for ascending
                out << getT() << "putstatic int " << class_name << "." << *$3 << endl;
            } else if (loop_var) {
                out << getT() << "iload " << loop_var->value->id << endl;
                out << getT() << "iconst_1" << endl;
                out << getT() << "iadd" << endl;
                out << getT() << "istore " << loop_var->value->id << endl;
            }
        } else {
            // Descending increment (decrement)
            if (loop_var && loop_var->is_global) {
                out << getT() << "getstatic int " << class_name << "." << *$3 << endl;
                out << getT() << "iconst_1" << endl;
                out << getT() << "isub" << endl;  // Subtract 1 for descending
                out << getT() << "putstatic int " << class_name << "." << *$3 << endl;
            } else if (loop_var) {
                out << getT() << "iload " << loop_var->value->id << endl;
                out << getT() << "iconst_1" << endl;
                out << getT() << "isub" << endl;
                out << getT() << "istore " << loop_var->value->id << endl;
            }
        }
        
        // Jump back to condition check
        out << getT() << "goto L_" << layers.top() << "_begin" << endl;
        
        // End label
        out << "L_" << layers.top() << "_exit:" << endl;
        out << getT() << "nop" << endl;
        layers.pop();
    }
;

function_arguments:
    function_arguments ',' expression
    {
        Trace("Reducing to function_arguments (recursive)\n");
        $1->push_back($3);
        $$ = $1;
    }
    | expression
    {
        Trace("Reducing to function_arguments (single_expression)\n");
        auto d = new vector<SymbolValue*>();
        d->push_back($1);
        $$ = d;
    }
    | /* empty */
    {
        Trace("Reducing to function_arguments (empty)\n");
        $$ = new vector<SymbolValue*>();
    }
    ;

scalar_type:
      BOOL   { Trace("Reducing to scalar_type (BOOL)\n"); $$ = _BOOL; g_current_scalar_type = _BOOL; }
    | INT    { Trace("Reducing to scalar_type (INT)\n"); $$ = _INT; g_current_scalar_type = _INT; }
    | FLOAT  { Trace("Reducing to scalar_type (FLOAT)\n"); $$ = _FLOAT; g_current_scalar_type = _FLOAT; }
    | STRING { Trace("Reducing to scalar_type (STRING)\n"); $$ = _STRING; g_current_scalar_type = _STRING; }
;

formal_parameter:
    scalar_type ID {
        Symbol* s = new Symbol(*$2, _VAR);
        s->value = new SymbolValue(_VAL, $1, 0);
        $$ = s;
    }
;

formal_parameters:
    formal_parameters ',' formal_parameter {
        $1->push_back($3);
        $$ = $1;
    }
    | formal_parameter {
        auto v = new vector<Symbol*>();
        v->push_back($1);
        $$ = v;
    }
    | /* empty */ {
        $$ = new vector<Symbol*>();
    }
;

%%

string getT(){
    string t = "";
    for(size_t i = 0; i < table_size ; i++){
        t += "\t";
    }
    return t;
}
void generateConstantLoad(SymbolValue* value) {
    if (value->dataType == _INT) {
        out << getT() << "sipush " << std::to_string(value->intVal) << endl;
    } else if (value->dataType == _BOOL) {
        out << getT() << "iconst_" << (value->bVal ? "1" : "0") << endl;
    } else if (value->dataType == _STRING) {
        out << getT() << "ldc " << *value->strVal << endl;
    } else if (value->dataType == _FLOAT) {
        if (value->floatVal < 0.0f) {
            out << getT() << "ldc " << std::to_string(-(value->floatVal)) << "F" << endl;
            out << getT() << "fneg" << endl;
        } else {
            out << getT() << "ldc " << std::to_string(value->floatVal) << "F" << endl;
        }
    }
}

int main(int argc, char* argv[]) {
    /* open the source program file */
    if (argc == 1) {
        yyin = stdin;
    } else if (argc == 2) {
        yyin = fopen(argv[1], "r");         /* open input file */
    } else {
        printf("Usage: ./parser filename\n");
    }

    string filename_str(argv[1]);
    size_t dot_pos = filename_str.find_last_of(".");
    if (dot_pos != string::npos) {
        class_name = filename_str.substr(0, dot_pos);
    } else {
        class_name = filename_str; // Fallback if no dot is found
    }

    out.open(class_name + ".jasm");
    if (!out.is_open()) {
        yyerror("can not open jasm for generating");
        exit(1);
    }
    
    /* perform parsing */
    if (yyparse() == 1)
        yyerror("Parsing error !");
    else
        printf("Parsed succeed!\n");

    out.close();
}

