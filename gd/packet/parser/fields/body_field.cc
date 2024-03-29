/*
 * Copyright 2019 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "fields/body_field.h"

BodyField::BodyField(ParseLocation loc) : PacketField(loc, "Body") {}

PacketField::Type BodyField::GetFieldType() const {
  return PacketField::Type::BODY;
}

Size BodyField::GetSize() const {
  return Size(0);
}

std::string BodyField::GetType() const {
  ERROR(this) << "No need to know the type of a body field.";
  return "BodyType";
}

void BodyField::GenGetter(std::ostream&, Size, Size) const {}

bool BodyField::GenBuilderParameter(std::ostream&) const {
  return false;
}

bool BodyField::HasParameterValidator() const {
  return false;
}

void BodyField::GenParameterValidator(std::ostream&) const {
  // There is no validation needed for a payload
}

void BodyField::GenInserter(std::ostream&) const {
  // Do nothing
}

void BodyField::GenValidator(std::ostream&) const {
  // Do nothing
}
