module Layout.Report.SelectorMode where

data SelectorMode = DropDown | RadioButton | Slider | TextBox

foreign data "com.clarifi.reporting.writers.SelectorMode" SelectorMode#

selectorMode# : SelectorMode -> SelectorMode#
selectorMode# DropDown = dropdown#
selectorMode# RadioButton = radioButton#
selectorMode# Slider = slider#
selectorMode# TextBox = textBox#

foreign private
  function "com.clarifi.reporting.writers.SelectorModes" "dropdown" dropdown# : SelectorMode#
  function "com.clarifi.reporting.writers.SelectorModes" "radioButton" radioButton# : SelectorMode#
  function "com.clarifi.reporting.writers.SelectorModes" "slider" slider# : SelectorMode#
  function "com.clarifi.reporting.writers.SelectorModes" "textBox" textBox# : SelectorMode#
