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

#pragma once

#include <map>
#include <set>
#include <string>

// Holds the definition of an enum.
class EnumDef {
 public:
  EnumDef(std::string name, int size);

  void AddEntry(std::string name, uint32_t value);

  bool HasEntry(std::string name) const;

  std::string GetTypeName() const;

  // data
  const std::string name_;
  int size_;
  std::map<uint32_t, std::string> constants_;
  std::set<std::string> entries_;
};
