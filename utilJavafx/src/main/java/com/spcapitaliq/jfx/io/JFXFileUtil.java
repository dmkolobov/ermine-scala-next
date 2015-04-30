package com.spcapitaliq.jfx.io;

import java.io.File;

/**
 *
 * @author mmorton
 *
 */
public class JFXFileUtil
{
  private JFXFileUtil() { /** static only */ }

  public static File appendExtensionIfMissing(File file, String extension)
  {
    String filename = file.getName();
    if(filename.endsWith(extension))
      return file;
    return appendExtension(file, extension);
  }

  public static File appendExtension(File file, String ext)
  {
    return new File(file.getParent(), file.getName() + ext );
  }
}
