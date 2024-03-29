%{
  #include <iostream>
  #include <vector>
  #include <list>
  #include <map>

  #include "declarations.h"
  #include "logging.h"
  #include "language_y.h"
  #include "field_list.h"
  #include "fields/all_fields.h"

  extern int yylex(yy::parser::semantic_type*, yy::parser::location_type*, void *);

  ParseLocation toParseLocation(yy::parser::location_type loc) {
    return ParseLocation(loc.begin.line);
  }
  #define LOC toParseLocation(yylloc)
%}

%parse-param { void* scanner }
%parse-param { Declarations* decls }
%lex-param { void* scanner }

%pure-parser
%glr-parser
%skeleton "glr.cc"

%expect-rr 0

%debug
%error-verbose
%verbose

%union {
  int integer;
  std::string* string;

  EnumDef* enum_definition;
  std::map<int, std::string>* enumeration_values;
  std::pair<int, std::string>* enumeration_value;

  PacketDef* packet_definition_value;
  FieldList* packet_field_definitions;
  PacketField* packet_field_type;

  std::map<std::string, std::variant<int64_t, std::string>>* constraint_list_t;
  std::pair<std::string, std::variant<int64_t, std::string>>* constraint_t;
}

%token <integer> INTEGER
%token <integer> IS_LITTLE_ENDIAN
%token <string> IDENTIFIER
%token <string> SIZE_MODIFIER
%token <string> STRING

%token ENUM "enum"
%token PACKET "packet"
%token PAYLOAD "payload"
%token BODY "body"
%token SIZE "size"
%token COUNT "count"
%token FIXED "fixed"
%token RESERVED "reserved"
%token GROUP "group"

%type<enum_definition> enum_definition
%type<enumeration_values> enumeration_list
%type<enumeration_value> enumeration

%type<packet_definition_value> packet_definition;
%type<packet_field_definitions> field_definition_list;
%type<packet_field_type> field_definition;
%type<packet_field_type> group_field_definition;
%type<packet_field_type> special_field_definition;
%type<packet_field_type> scalar_field_definition;
%type<packet_field_type> size_field_definition;
%type<packet_field_type> payload_field_definition;
%type<packet_field_type> body_field_definition;
%type<packet_field_type> fixed_field_definition;
%type<packet_field_type> reserved_field_definition;

%type<constraint_list_t> constraint_list;
%type<constraint_t> constraint;
%destructor { std::cout << "DESTROYING STRING " << *$$ << "\n"; delete $$; } IDENTIFIER STRING SIZE_MODIFIER

%%

file
  : IS_LITTLE_ENDIAN declarations
  {
    decls->is_little_endian = ($1 == 1);
    if (decls->is_little_endian) {
      DEBUG() << "LITTLE ENDIAN ";
    } else {
      DEBUG() << "BIG ENDIAN ";
    }
  }

declarations
  : /* empty */
  | declarations declaration

declaration
  : enum_definition
    {
      std::cerr << "FOUND ENUM\n\n";
      decls->AddEnumDef($1->name_, std::move(*$1));
      delete $1;
    }
  | packet_definition
    {
      std::cerr << "FOUND PACKET\n\n";
      decls->AddPacketDef($1->name_, std::move(*$1));
      delete $1;
    }
  | group_definition
    {
      // All actions are handled in group_definition
    }

enum_definition
  : ENUM IDENTIFIER ':' INTEGER '{' enumeration_list ',' '}'
    {
      std::cerr << "Enum Declared: name=" << *$2
                << " size=" << $4 << "\n";

      $$ = new EnumDef(std::move(*$2), $4);
      for (const auto& e : *$6) {
        $$->AddEntry(e.second, e.first);
      }
      delete $2;
      delete $6;
    }

enumeration_list
  : enumeration
    {
      std::cerr << "Enumerator with comma\n";
      $$ = new std::map<int, std::string>();
      $$->insert(std::move(*$1));
      delete $1;
    }
  | enumeration_list ',' enumeration
    {
      std::cerr << "Enumerator with list\n";
      $$ = $1;
      $$->insert(std::move(*$3));
      delete $3;
    }

enumeration
  : IDENTIFIER '=' INTEGER
    {
      std::cerr << "Enumerator: name=" << *$1
                << " value=" << $3 << "\n";
      $$ = new std::pair($3, std::move(*$1));
      delete $1;
    }

group_definition
  : GROUP IDENTIFIER '{' field_definition_list '}'
    {
      decls->AddGroupDef(*$2, $4);
      delete $2;
    }

packet_definition
  : PACKET IDENTIFIER '{' field_definition_list '}'  /* Packet with no parent */
    {
      auto&& packet_name = *$2;
      auto&& field_definition_list = *$4;

      DEBUG() << "Packet " << packet_name << " with no parent";
      DEBUG() << "PACKET FIELD LIST SIZE: " << field_definition_list.size();
      auto packet_definition = new PacketDef(std::move(packet_name), std::move(field_definition_list));
      packet_definition->AssignSizeFields();

      $$ = packet_definition;
      delete $2;
      delete $4;
    }
  | PACKET IDENTIFIER ':' IDENTIFIER '{' field_definition_list '}'
    {
      auto&& packet_name = *$2;
      auto&& parent_packet_name = *$4;
      auto&& field_definition_list = *$6;

      DEBUG() << "Packet " << packet_name << " with parent " << parent_packet_name << "\n";
      DEBUG() << "PACKET FIELD LIST SIZE: " << field_definition_list.size() << "\n";

      auto parent_packet = decls->GetPacketDef(parent_packet_name);
      if (parent_packet == nullptr) {
        ERRORLOC(LOC) << "Could not find packet " << parent_packet_name
                  << " used as parent for " << packet_name;
      }

      auto packet_definition = new PacketDef(std::move(packet_name), std::move(field_definition_list), parent_packet);
      packet_definition->AssignSizeFields();

      $$ = packet_definition;
      delete $2;
      delete $4;
      delete $6;
    }
  | PACKET IDENTIFIER ':' IDENTIFIER '(' constraint_list ')' '{' field_definition_list '}'
    {
      auto&& packet_name = *$2;
      auto&& parent_packet_name = *$4;
      auto&& constraints = *$6;
      auto&& field_definition_list = *$9;

      DEBUG() << "Packet " << packet_name << " with parent " << parent_packet_name << "\n";
      DEBUG() << "PACKET FIELD LIST SIZE: " << field_definition_list.size() << "\n";
      DEBUG() << "CONSTRAINT LIST SIZE: " << constraints.size() << "\n";

      auto parent_packet = decls->GetPacketDef(parent_packet_name);
      if (parent_packet == nullptr) {
        ERRORLOC(LOC) << "Could not find packet " << parent_packet_name
                  << " used as parent for " << packet_name;
      }

      auto packet_definition = new PacketDef(std::move(packet_name), std::move(field_definition_list), parent_packet);
      packet_definition->AssignSizeFields();

      for (const auto& constraint : constraints) {
        const auto& constraint_name = constraint.first;
        const auto& constraint_value = constraint.second;
        DEBUG() << "Parent constraint on " << constraint_name;
        packet_definition->AddParentConstraint(constraint_name, constraint_value);
      }

      $$ = packet_definition;

      delete $2;
      delete $4;
      delete $6;
      delete $9;
    }

field_definition_list
  : /* empty */
    {
      std::cerr << "Empty Field definition\n";
      $$ = new FieldList();
    }
  | field_definition
    {
      std::cerr << "Field definition\n";
      $$ = new FieldList();

      if ($1->GetFieldType() == PacketField::Type::GROUP) {
        auto group_fields = static_cast<GroupField*>($1)->GetFields();
	FieldList reversed_fields(group_fields->rbegin(), group_fields->rend());
        for (auto& field : reversed_fields) {
          $$->PrependField(field);
        }
	delete $1;
        break;
      }

      $$->PrependField($1);
    }
  | field_definition ',' field_definition_list
    {
      std::cerr << "Field definition with list\n";
      $$ = $3;

      if ($1->GetFieldType() == PacketField::Type::GROUP) {
        auto group_fields = static_cast<GroupField*>($1)->GetFields();
	FieldList reversed_fields(group_fields->rbegin(), group_fields->rend());
        for (auto& field : reversed_fields) {
          $$->PrependField(field);
        }
	delete $1;
        break;
      }

      $$->PrependField($1);
    }

field_definition
  : group_field_definition
    {
      DEBUG() << "Group Field";
      $$ = $1;
    }
  | special_field_definition
    {
      std::cerr << "Special field\n";
      $$ = $1;
    }
  | scalar_field_definition
    {
      std::cerr << "Scalar field\n";
      $$ = $1;
    }
  | size_field_definition
    {
      std::cerr << "Size field\n";
      $$ = $1;
    }
  | body_field_definition
    {
      std::cerr << "Body field\n";
      $$ = $1;
    }
  | payload_field_definition
    {
      std::cerr << "Payload field\n";
      $$ = $1;
    }
  | fixed_field_definition
    {
      std::cerr << "Fixed field\n";
      $$ = $1;
    }
  | reserved_field_definition
    {
      std::cerr << "Reserved field\n";
      $$ = $1;
    }

group_field_definition
  : IDENTIFIER
    {
      auto group = decls->GetGroupDef(*$1);
      if (group == nullptr) {
        ERRORLOC(LOC) << "Could not find group with name " << *$1;
      }

      std::list<PacketField*>* expanded_fields;
      expanded_fields = new std::list<PacketField*>(group->begin(), group->end());
      $$ = new GroupField(LOC, expanded_fields);
      delete $1;
    }
  | IDENTIFIER '{' constraint_list '}'
    {
      std::cerr << "Group with fixed field(s) " << *$1 << "\n";
      auto group = decls->GetGroupDef(*$1);
      if (group == nullptr) {
        ERRORLOC(LOC) << "Could not find group with name " << *$1;
      }

      std::list<PacketField*>* expanded_fields = new std::list<PacketField*>();
      for (const auto field : *group) {
        const auto constraint = $3->find(field->GetName());
        if (constraint != $3->end()) {
          if (field->GetFieldType() == PacketField::Type::SCALAR) {
            std::cerr << "Fixing group scalar value\n";
            expanded_fields->push_back(new FixedField(field->GetSize().bits(), std::get<int64_t>(constraint->second), LOC));
          } else if (field->GetFieldType() == PacketField::Type::ENUM) {
            std::cerr << "Fixing group enum value\n";

            auto enum_def = decls->GetEnumDef(field->GetType());
            if (enum_def == nullptr) {
              ERRORLOC(LOC) << "No enum found of type " << field->GetType();
            }
            if (!enum_def->HasEntry(std::get<std::string>(constraint->second))) {
              ERRORLOC(LOC) << "Enum " << field->GetType() << " has no enumeration " << std::get<std::string>(constraint->second);
            }

            expanded_fields->push_back(new FixedField(enum_def, std::get<std::string>(constraint->second), LOC));
          } else {
            ERRORLOC(LOC) << "Unimplemented constraint of type " << field->GetType();
          }
          $3->erase(constraint);
        } else {
          expanded_fields->push_back(field);
        }
      }
      if ($3->size() > 0) {
        ERRORLOC(LOC) << "Could not find member " << $3->begin()->first << " in group " << *$1;
      }

      $$ = new GroupField(LOC, expanded_fields);
      delete $1;
      delete $3;
    }

constraint_list
  : constraint ',' constraint_list
    {
      std::cerr << "Group field value list\n";
      $3->insert(*$1);
      $$ = $3;
      delete($1);
    }
  | constraint
    {
      std::cerr << "Group field value\n";
      $$ = new std::map<std::string, std::variant<int64_t, std::string>>();
      $$->insert(*$1);
      delete($1);
    }

constraint
  : IDENTIFIER '=' INTEGER
    {
      std::cerr << "Group with a fixed integer value=" << $1 << " value=" << $3 << "\n";

      $$ = new std::pair(*$1, std::variant<int64_t,std::string>($3));
      delete $1;
    }
  | IDENTIFIER '=' IDENTIFIER
    {
      DEBUG() << "Group with a fixed enum field value=" << *$3 << " enum=" << *$1;

      $$ = new std::pair(*$1, std::variant<int64_t,std::string>(*$3));
      delete $1;
      delete $3;
    }

special_field_definition
  : IDENTIFIER ':' IDENTIFIER
    {
      std::cerr << "Special field " << *$1 << " : " << *$3 << "\n";
      if (auto enum_def = decls->GetEnumDef(*$3)) {
          $$ = new EnumField(*$1, *enum_def, "", LOC);
      } else {
          ERRORLOC(LOC) << "No type with this name\n";
      }
      delete $1;
      delete $3;
    }

scalar_field_definition
  : IDENTIFIER ':' INTEGER
    {
      std::cerr << "Scalar field " << *$1 << " : " << $3 << "\n";
      $$ = new ScalarField(*$1, $3, LOC);
      delete $1;
    }

body_field_definition
  : BODY
    {
      std::cerr << "Body field\n";
      $$ = new BodyField(LOC);
    }

payload_field_definition
  : PAYLOAD ':' '[' SIZE_MODIFIER ']'
    {
      std::cerr << "Payload field with modifier " << *$4 << "\n";
      $$ = new PayloadField(*$4, LOC);
      delete $4;
    }
  | PAYLOAD ':' '[' INTEGER ']'
    {
      ERRORLOC(LOC) << "Payload fields can only be dynamically sized.";
    }
  | PAYLOAD
    {
      std::cerr << "Payload field\n";
      $$ = new PayloadField("", LOC);
    }

size_field_definition
  : SIZE '(' IDENTIFIER ')' ':' INTEGER
    {
      std::cerr << "Size field defined\n";
      $$ = new SizeField(*$3, $6, false, LOC);
      delete $3;
    }
  | SIZE '(' PAYLOAD ')' ':' INTEGER
    {
      std::cerr << "Size for payload defined\n";
      $$ = new SizeField("Payload", $6, false, LOC);
    }
  | COUNT '(' IDENTIFIER ')' ':' INTEGER
    {
      std::cerr << "Count field defined\n";
      $$ = new SizeField(*$3, $6, true, LOC);
      delete $3;
    }
  | COUNT '(' PAYLOAD ')' ':' INTEGER
    {
      std::cerr << "Count for payload defined\n";
      $$ = new SizeField("Payload", $6, true, LOC);
      ERRORLOC(LOC) << "Can not use count to describe payload fields.";
    }

fixed_field_definition
  : FIXED '=' INTEGER ':' INTEGER
    {
      std::cerr << "Fixed field defined value=" << $3 << " size=" << $5 << "\n";
      $$ = new FixedField($5, $3, LOC);
    }
  | FIXED '=' IDENTIFIER ':' IDENTIFIER
    {
      DEBUG() << "Fixed enum field defined value=" << *$3 << " enum=" << *$5;
      if (auto enum_def = decls->GetEnumDef(*$5)) {
        if (!enum_def->HasEntry(*$3)) {
          ERRORLOC(LOC) << "Previously defined enum " << enum_def->GetTypeName() << " has no entry for " << *$3;
        }

        $$ = new FixedField(enum_def, *$3, LOC);
      } else {
        ERRORLOC(LOC) << "No enum found with name " << *$5;
      }

      delete $3;
      delete $5;
    }

reserved_field_definition
  : RESERVED ':' INTEGER
    {
      std::cerr << "Reserved field of size=" << $3 << "\n";
      $$ = new ReservedField($3, LOC);
    }

%%


void yy::parser::error(const yy::parser::location_type& loc, const std::string& error) {
  std::cerr << error << " at location " << loc << "\n";
  abort();
}
