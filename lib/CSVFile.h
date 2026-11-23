#pragma once
#include "afx.h"
#include "StdioFileEx.h"

class CCSVFile : public CStdioFileEx
{
public:
  CCSVFile();
  ~CCSVFile();
  bool ReadData(CStringArray &arr);
  void WriteData(CStringArray &arr);
};
