#ifndef SYMBOLTABLE_H
#define SYMBOLTABLE_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>
using namespace std;

#define MAX_NAME 256
#define MAX_SCOPE 100

const int _INT = 0;
const int _FLOAT = 1;
const int _BOOL = 2;
const int _STRING = 3;
const int _VOID = 4;

const int _ALL = -1;
const int _VAL = 0;
const int _VAR = 1;
const int _ARRAY = 2;
const int _FUN = 3;

extern bool isMain;

typedef struct SymbolValue {
    int intVal;
    float floatVal;
    char charVal;
    string *strVal;
    bool bVal;

    int type; // (e.g., val, var, array, function)
    int dataType; // Type of the value (e.g., int, float, char, string, bool)
    
    int id;
    
    SymbolValue() { }
    SymbolValue(int t, int d, int i) : type(t), dataType(d), intVal(i) { }
    SymbolValue(int t, int d, float f) : type(t), dataType(d), floatVal(f) { }
    SymbolValue(int t, int d, char c) : type(t), dataType(d), charVal(c) { }
    SymbolValue(int t, int d, string *s) : type(t), dataType(d), strVal(s) { }
    SymbolValue(int t, int d, bool b) : type(t), dataType(d), bVal(b) { }

    // Copy constructor for SymbolValue
    SymbolValue(const SymbolValue& other) : type(other.type), dataType(other.dataType), strVal(nullptr) {
        switch (dataType) {
            case _INT: intVal = other.intVal; break;
            case _FLOAT: floatVal = other.floatVal; break;
            case _BOOL: bVal = other.bVal; break;
            case _STRING:
                if (other.strVal) strVal = new string(*(other.strVal));
                // else strVal remains nullptr, which is correct
                break;
            // Add charVal if _CHAR type is used
            // case _CHAR: charVal = other.charVal; break; 
            default:
                // Default initialization or error for unhandled types
                // For now, ensure intVal is initialized if others are not applicable,
                // though specific type handling is better.
                intVal = 0; 
                break;
        }
    }
} SymbolValue;
typedef struct Symbol {
    string name;
    int type; // Type of the symbol (e.g., int, float, char, etc.)
    int is_const; // 1 if the symbol is constant, 0 otherwise
    SymbolValue *value; // Value of the symbol
    bool is_global; // 1 if the symbol is global, 0 otherwise

    int size;
    vector<SymbolValue*> *arr;
    vector<Symbol*> *formal_parameters;

    Symbol() : value(nullptr), arr(nullptr), formal_parameters(nullptr) {}
    Symbol(string n, int t) : name(n), type(t), is_const(0), value(nullptr), arr(nullptr), formal_parameters(nullptr) {}
    Symbol(string n, int t, int c) : name(n), type(t), is_const(c), value(nullptr), arr(nullptr), formal_parameters(nullptr) {}

    // Copy constructor for Symbol (focused on copying formal parameters into a new scope)
    Symbol(const Symbol& other) :
        name(other.name),
        type(other.type),
        is_const(other.is_const),
        value(nullptr),
        size(other.size),
        arr(nullptr),
        formal_parameters(nullptr)
    {
        if (other.value) {
            this->value = new SymbolValue(*(other.value)); // Uses SymbolValue copy constructor
        }

        // If the symbol being copied is an array, its 'arr' field needs deep copying.
        // This is essential if array parameters are to be handled correctly.
        if (other.arr) {
            this->arr = new vector<SymbolValue*>();
            for (const auto* sv : *(other.arr)) {
                if (sv) {
                    this->arr->push_back(new SymbolValue(*sv));
                } else {
                    this->arr->push_back(nullptr); // Or handle as an error
                }
            }
        }
        
        // A formal parameter symbol itself typically does not have its own 'formal_parameters'.
        // If 'other' could be a function symbol (e.g. for function pointers),
        // then 'other.formal_parameters' would need a deep recursive copy.
        // For simple parameters (like 'int a'), 'other.formal_parameters' is nullptr.
        if (other.formal_parameters) {
            // This part would be for deep copying a function symbol, including its parameter list.
            // For copying a simple parameter *into* a scope, this is usually not applicable
            // as the parameter 'other' would have 'formal_parameters == nullptr'.
            this->formal_parameters = new vector<Symbol*>();
            for (const auto* sym_param : *(other.formal_parameters)) {
                if (sym_param) {
                    this->formal_parameters->push_back(new Symbol(*sym_param)); // Recursive copy
                } else {
                    this->formal_parameters->push_back(nullptr);
                }
            }
        }
    }
} Symbol;

typedef struct SymbolTable {
    vector<Symbol*> symbols; // Use vector instead of linked list
    struct SymbolTable *parent;

    bool isGlobal() { return (parent == nullptr); }

    SymbolTable() {}
} SymbolTable;

// Function to create a new symbol table
SymbolTable* create_symbol_table(SymbolTable *parent);

// Function to insert a symbol into the current symbol table
int insert_symbol(SymbolTable *table, Symbol *symbol);

// Function to lookup a symbol in the current and parent symbol tables
Symbol* lookup_symbol(SymbolTable *table, string name, int search_parent);

// Function to delete the current symbol table and free memory
void delete_symbol_table(SymbolTable *table);

// Function to print the symbol table for debugging
void dump_symbol_table(SymbolTable *table);

SymbolValue* callFunction(Symbol* func, vector<SymbolValue*>* args);

string toTypeString(int t);

string toDataTypeString(int t);

#endif 
