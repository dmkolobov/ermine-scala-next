package com.clarifi.reporting.util;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.StringTokenizer;

public class SpaceConverter {
    /**
     * Replaces space characters with newlines to allow a long String to
     * be spread out over several lines. A threshold is specified that
     * must be exceeded to cause a space to be replaced in order to prevent
     * small substrings from wrapping over aggressively.
     *
     * @param original
     * @param threshold
     * @return
     */
    public static String convertSpaceToNewlines( String original, int threshold )
    {
        if( original.indexOf(' ') == -1 )
            return original;
        StringTokenizer sToke = new StringTokenizer(original, " ");
        List<String> tokens = new ArrayList<String>();
        while( sToke.hasMoreTokens() )
            tokens.add(sToke.nextToken());

        StringBuilder converted = new StringBuilder( original.length() );
        int count = 0;
        for( Iterator<String> i = tokens.iterator(); i.hasNext(); )
        {
            String token = i.next();
            int length = token.length();
            if( count == 0 )
            {
                converted.append(token);
                count += length;
            }
            else if( count + length < threshold )
            {
                converted.append(' ').append(token);
                count += length + 1;
            }
            else
            {
                converted.append('\n').append(token);
                count = length;
            }
        }
        return converted.toString();
    }
}