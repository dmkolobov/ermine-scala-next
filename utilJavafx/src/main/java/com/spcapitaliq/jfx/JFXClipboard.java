package com.spcapitaliq.jfx;

import java.util.*;

import javafx.application.Platform;
import javafx.collections.ObservableList;
import javafx.event.EventHandler;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.control.*;
import javafx.scene.control.TableView.TableViewSelectionModel;
import javafx.scene.image.WritableImage;
import javafx.scene.input.*;
import javafx.scene.text.Text;

import com.sun.javafx.scene.control.skin.LabeledText;
import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.JFXTraverser.InstanceOfStrategy;
import com.spcapitaliq.jfx.action.*;
import com.spcapitaliq.jfx.concurrency.BlockerModal;
import com.spcapitaliq.jfx.concurrency.BlockerTask;
import com.spcapitaliq.jfx.concurrency.RunLaterWaiter;
import com.spcapitaliq.jfx.image.JFXImageUtil;
import com.spcapitaliq.jfx.table.TableViewDataProvider;

/**
 *
 * @author mmorton
 *
 */
public class JFXClipboard
{
  private static final Logger _log = Logger.getLogger( JFXClipboard.class );

  private static final char NEWLINE = '\n';
  private static final char TAB = '\t';
  private static final Logger Log = Logger.getLogger(JFXClipboard.class);

  private JFXClipboard() {}

  public static abstract class ToClipboardLogic extends BlockerTask<Object>
  {
    protected abstract void populateContent(ClipboardContent content);

    @Override
    protected final Object call()
    {
      this.updateMessage("Copying table to clipboard...");

      final long referenceTime = System.currentTimeMillis();
      final ClipboardContent content = new ClipboardContent();
      populateContent(content);
      RunLaterWaiter.runLaterAndWait(new Runnable()
      {
        @Override
        public void run()
        {
          Clipboard.getSystemClipboard().setContent(content);
        }
      });
      JFXUtil.provideMinimumPause(referenceTime, 300);

      return null;
    }
  }

  public static <S, ST> void addCopyTableHotkey( final TableView<S> table, final TableViewDataProvider<S, ST> provider )
  {
    JFXUtil.runIfSafeOrOnFirstSized(table, new Runnable()
    {
      @Override
      public void run()
      {
        table.setOnKeyReleased(new EventHandler<KeyEvent>()
        {
          private final KeyCombination copy = new KeyCodeCombination(KeyCode.C, KeyCombination.CONTROL_DOWN);

          @Override
          public void handle(KeyEvent ke)
          {
            if(copy.match(ke))
            {
              copyTableSelection(table, provider);
            }
          }
        });
      }
    });
  }

  private static void describeMenuSelection(TableView<?> table)
  {
    final TableViewSelectionModel<?> selectionModel = table.getSelectionModel();
    StringBuilder msg = new StringBuilder();
    if(selectionModel.isEmpty())
    {
      msg.append("Table has no selection");
    }
    else
    {
      final ObservableList<?> selectedItems = selectionModel.getSelectedItems();
      msg.append("Table row selection:");
      for(Object o : selectedItems)
        msg.append('\n').append(o);
    }
    Log.debug(msg.toString());
  }

  /**
   * Sigh, generics warning suppressed due to API limitation:
   *  https://javafx-jira.kenai.com/browse/RT-29175
   */
  private static <S> ObservableList<TablePosition<S, ?>>
    getSelectedCells(TableView.TableViewSelectionModel<S> sm)
  {
    @SuppressWarnings("rawtypes")
    ObservableList<TablePosition> badout = sm.getSelectedCells();
    @SuppressWarnings("unchecked")
    ObservableList<TablePosition<S, ?>> out =
      (ObservableList<TablePosition<S, ?>>) ((ObservableList) badout);
    return out;
  }

  public static <S, ST> void copyTableSelection(final TableView<S> table,
                                                final TableViewDataProvider<S, ST> provider)
  {
    class CopySelectionTableLogic extends ToClipboardLogic
    {
      @Override
      protected void populateContent(ClipboardContent content)
      {
        ObservableList<TablePosition<S, ?>> posList = getSelectedCells(table.getSelectionModel());

        final List<TablePosition<S, ?>> sortedAndCompletedPosList = SelectionData.processSelection(posList);

        /* push the completed selection back to the table so user will see */
        Platform.runLater(new Runnable()
        {
          @Override
          public void run()
          {
            applySelection(table, sortedAndCompletedPosList);
          }});

        SelectionData<S> selection = new SelectionData<>(posList);
        ST data = provider.prepareData( table.getSortOrder(), selection._columns, selection._rows);
        Map<TableColumn<S, ?>, Integer> counts = calculateSyntheticColumns(data, table, provider);

        content.putString( selectionToTabDelimitedPlainText( table, sortedAndCompletedPosList, provider, data, counts ) );
        content.putHtml( selectionToHTMLTable( table, sortedAndCompletedPosList, provider, data, counts ) );
      }
    }
    new BlockerModal().show(table, new CopySelectionTableLogic());
  }

  private static <S> void applySelection( TableView<S> table, List<TablePosition<S, ?>> posList)
  {
    TableViewSelectionModel<S> selectionModel = table.getSelectionModel();
    selectionModel.clearSelection();
    for(TablePosition<S, ?> pos : posList)
    {
      selectionModel.select(pos.getRow(), pos.getTableColumn());
    }
  }

  public static <S, ST> String copyFullTableToClipboard(TableView<S> table, TableViewDataProvider<S, ST> provider, boolean includeHeader)
  {
    ClipboardContent content = new ClipboardContent();
    String result = copyFullTableToClipboard(table, provider, includeHeader, content);
    Clipboard.getSystemClipboard().setContent(content);
    return result;
  }

  public static <S, ST> String copyFullTableToClipboard(TableView<S> table, TableViewDataProvider<S, ST> provider, boolean includeHeader, ClipboardContent content)
  {
    try
    {
      ObservableList<TableColumn<S, ?>> columns = table.getColumns();
      ST data = provider.prepareData(table.getSortOrder(), columns, null);
      Map<TableColumn<S, ?>, Integer> counts = calculateSyntheticColumns(data, table, provider);
      String result = fullTableToTabDelimitedPlainText( data, table, includeHeader, provider, counts );
      content.putString( result );
      content.putHtml( fullTableToHTMLTable( data, table, includeHeader, provider, counts ) );

      return result;
    }
    catch( Throwable t )
    {
      String msg = "Failed to copy full table to clipboard";
      Log.warn(msg, t);
      return msg + " " + t;
    }
  }

  private static class SelectionData<S>
  {
    private final Collection<TableColumn<S, ?>> _columns;

    private final Collection<Integer> _rows;

    SelectionData(ObservableList<TablePosition<S, ?>> posList)
    {
      _rows = new LinkedList<>();
      _columns = new HashSet<TableColumn<S, ?>>();
      for (TablePosition<S, ?> p : posList)
      {
        _columns.add(p.getTableColumn());
        int row = p.getRow();
        if(row != -1)
          _rows.add(Integer.valueOf(row));
      }
    }

    /**
     * Completes the selection to conform to Swing's selection behavior
     * (as found in 5.2). The rule is if a cell is selected, every other
     * row with a selection must include the cell in the same column.
     *
     * @param posList
     * @return
     */
    private static <S> List<TablePosition<S, ?>> processSelection(List<TablePosition<S, ?>> posList)
    {
      if(posList.isEmpty())
        return Collections.emptyList();

      TableView<S> table = posList.get(0).getTableView();

      posList = sortPositionList(posList);

      Set<TableColumn<S, ?>> involvedColumns = new HashSet<>();
      for(TablePosition<S, ?> pos : posList)
      {
        involvedColumns.add(pos.getTableColumn());
      }

      Log.debug("Selection has " + involvedColumns.size() + " columns involved");

      int[] colIxes = new int[involvedColumns.size()];
      final ObservableList<TableColumn<S, ?>> allCols = table.getColumns();
      int i = 0, j = 0;
      for(TableColumn<S, ?> col : allCols)
      {
        if(involvedColumns.contains(col))
          colIxes[i++] = j;
        j++;
      }

      List<TablePosition<S, ?>> processed = new ArrayList<>(posList.size());

      int priorRow = -1;
      int colIx = -1;
      for(TablePosition<S, ?> pos : posList)
      {
        int row = pos.getRow();
        int col = pos.getColumn();

        //Log.trace("Processing: " + pos);

        if(row > priorRow)
        {
          if(colIx != -1)
          {
            for(; colIx < colIxes.length; colIx++)
            {
              //Log.trace("Inserted1: [" + priorRow + "," + colIxes[colIx] + ']');
              processed.add(new TablePosition<>(table, priorRow, allCols.get(colIxes[colIx])));
            }
          }

          priorRow = row;
          colIx = 0;
        }

        for(; colIxes[colIx] < col; colIx++)
        {
          //Log.trace("Inserted2: [" + row + "," + colIxes[colIx] + ']');
          processed.add(new TablePosition<>(table, row, allCols.get(colIxes[colIx])));
        }

        processed.add(pos);
        //Log.trace("Added [" + row + "," + col + ']');

        if(colIxes[colIx] == col)
          colIx++;
      }

      // insert any remaining
      if(colIx != -1)
      {
        for(; colIx < colIxes.length; colIx++)
        {
          //Log.trace("Post Inserted1: [" + priorRow + "," + colIxes[colIx] + ']');
          processed.add(new TablePosition<>(table, priorRow, allCols.get(colIxes[colIx])));
        }
      }

      Log.debug("Added " + (processed.size() - posList.size()) + " cells to complete selection.");

      return processed;
    }

    /**
     * Sort to make sure that positions sort
     * @param posList
     * @return
     */
    private static <S> List<TablePosition<S, ?>> sortPositionList(List<TablePosition<S, ?>> posList)
    {
      List<TablePosition<S, ?>> sorted = new ArrayList<>(posList);
      Collections.sort(sorted, new TablePositionComparator<S>());
      return sorted;
    }

    private static class TablePositionComparator<S> implements Comparator<TablePosition<S, ?>>
    {
      @Override
      public int compare(TablePosition<S, ?> o1, TablePosition<S, ?> o2)
      {
        int val = Integer.compare(o1.getRow(), o2.getRow());
        if(val != 0)
          return val;
        return Integer.compare(o1.getColumn(), o2.getColumn());
      }
    }
  }

  private static <S,ST> String selectionToTabDelimitedPlainText( TableView<S> table, List<TablePosition<S, ?>> posList,
                                                                 TableViewDataProvider<S,ST> provider, ST data, Map<TableColumn<S, ?>, Integer> counts )
  {
    int old_r = -1;
    StringBuilder clipboardString = new StringBuilder();
    for (TablePosition<S, ?> p : posList)
    {
      int r = p.getRow();
      int c = p.getColumn();
      if(r != -1 && c != -1)
      {
        if (old_r == r)
          clipboardString.append(TAB);
        else if (old_r != -1)
          clipboardString.append(NEWLINE);

        final List<String> datas = provider.provideCellData(data, table.getColumns().get(c), r);
        appendCellDataTabDelimitedPlainText(clipboardString, counts, p.getTableColumn(), datas);
      }
      old_r = r;
    }
    return clipboardString.toString();
  }

  /**
   * Some columns, like in a drilldown, express a hierarchy. Such a column
   * must be expanded to "synthetic colunns".
   *
   * This function calls provideCellData on each cell to determine on a
   * per column basis the max count of synthetic columns.
   *
   * @param data
   * @param table
   * @param provider
   * @param <S>
   * @param <ST>
   * @return
   */
  private static <S, ST> Map<TableColumn<S, ?>, Integer> calculateSyntheticColumns( ST data, TableView<S> table, TableViewDataProvider<S, ST> provider)
  {
    Map<TableColumn<S, ?>, Integer> map = new HashMap<>();

    ObservableList<TableColumn<S, ?>> columns = table.getColumns();

    int numRows = table.getItems().size();
    if(0 == numRows)
    {
      /** if no rows then nothing is expanded and all columns are width 1 */
      for (TableColumn<S, ?> column : columns)
        map.put(column, Integer.valueOf(1));
    }
    else
    {
      for (int i = 0 ; i < numRows ; i++)
      {
        int columnIndex = 0;
        for (TableColumn<S, ?> column : columns)
        {
          try
          {
            int width = provider.provideCellData(data, column, i).size();
            Integer count = map.get(column);
            if (null == count || width > count.intValue())
              map.put(column, Integer.valueOf(width));
          }
          catch (Exception e)
          {
            _log.error("Failed to calculateSyntheticColumns for row: " + i + " and column: " + columnIndex);
            throw e;
          }
          ++columnIndex;
        }
      }
    }

    if(Log.isDebugEnabled())
    {
      StringBuilder debug = new StringBuilder("Synthetic column counts:");

      for(TableColumn<S, ?> column : columns)
        debug.append("\n\t").append(column.getText()).append(": ").append(map.get(column).toString());
      Log.debug(debug.toString());
    }

    return map;
  }

  private static <S, T> String resolveColumnText(TableColumn<S, T> column)
  {
    String text = column.getText();
    if(null == text || text.isEmpty())
    {
      Log.debug("column's text is empty, diving...");
      Node graphic = column.getGraphic();
      if(null != graphic)
      {
        class NonEmptyLabelStrategy extends InstanceOfStrategy<Label>
        {
          NonEmptyLabelStrategy()
          {
            super(Label.class);
          }

          protected boolean isDirectHit(Label node)
          {
            return !node.getText().isEmpty();
          }
        }

        Label hit = JFXTraverser.breadthFirstSearch(graphic, new NonEmptyLabelStrategy());
        if(null != hit)
        {
          text = hit.getText();
          Log.debug("Found text for column: " + text);
        }
      }
    }
    return text;
  }

  private static <S, ST> String fullTableToTabDelimitedPlainText( ST data, TableView<S> table, boolean includeHeaders, TableViewDataProvider<S, ST> provider, Map<TableColumn<S, ?>, Integer> counts )
  {
    StringBuilder clipboardString = new StringBuilder();

    ObservableList<TableColumn<S, ?>> columns = table.getColumns();

    boolean first = true;
    if( includeHeaders )
    {
      for( TableColumn<S, ?> column : columns )
      {
        if( !first )
          clipboardString.append(TAB);
        clipboardString.append( resolveColumnText(column) );
        int count = counts.get(column).intValue();
        for(int i = 1; i < count; i++)
          clipboardString.append(TAB);
        first = false;
      }
      clipboardString.append('\n');
    }

    int numRows = table.getItems().size();
    for( int i = 0; i < numRows; i++ )
    {
      if( i != 0 )
        clipboardString.append('\n');

      first = true;
      for( TableColumn<S, ?> column : columns )
      {
        if( !first )
          clipboardString.append(TAB);
        final List<String> datas = provider.provideCellData(data, column, i);
        appendCellDataTabDelimitedPlainText(clipboardString, counts, column, datas);
        first = false;
      }
    }

    return clipboardString.toString();
  }

  private static <S> void appendCellDataTabDelimitedPlainText(
    StringBuilder clipboardString, Map<TableColumn<S, ?>, Integer> counts,
    TableColumn<S, ?> column, final List<String> datas)
  {
    boolean first = true;
    for(String datum : datas)
    {
      if( !first )
        clipboardString.append(TAB);
      clipboardString.append(datum);
      first = false;
    }
    int count = counts.get(column).intValue();
    for(int j = datas.size(); j < count; j++)
      clipboardString.append(TAB);
  }

  private static class HTMLTableHelper
  {
    private final StringBuilder _html;

    HTMLTableHelper()
    {
      _html = new StringBuilder( "<html><body><table>" );
    }

    private void beginRow()
    {
      _html.append("<tr>");
    }

    private void endRow()
    {
      _html.append("</tr>");
    }

    private void add( Object cell )
    {
      _html.append("<td>");
      _html.append(cell);
      _html.append("</td>");
    }

    private String conclude()
    {
      _html.append( "</table></body></html>" );
      return _html.toString();
    }
  }

  private static <S, ST> String selectionToHTMLTable( TableView<S> table, List<TablePosition<S, ?>> posList,
                                                      TableViewDataProvider<S,ST> provider, ST data, Map<TableColumn<S, ?>, Integer> counts )
  {
    HTMLTableHelper html = new HTMLTableHelper();

    final ObservableList<TableColumn<S, ?>> columns = table.getColumns();

    boolean insideRow = false;
    int old_r = -1;
    for (TablePosition<S, ?> p : posList)
    {
      int r = p.getRow();
      int c = p.getColumn();

      if(r != -1 && c != -1)
      {

        if (old_r != -1 && old_r != r)
        {
          html.endRow();
          insideRow = false;
        }

        if( !insideRow )
        {
          html.beginRow();
          insideRow = true;
        }

        List<String> datas = provider.provideCellData(data, columns.get(c), r);
        appendCellDataHTML(html, counts, p.getTableColumn(), datas);
      }

      old_r = r;
    }

    return html.conclude();
  }

  private static <S, ST> String fullTableToHTMLTable( ST data, TableView<S> table, boolean includeHeaders,
                                                      TableViewDataProvider<S, ST> provider, Map<TableColumn<S, ?>, Integer> counts )
  {
    HTMLTableHelper html = new HTMLTableHelper();

    ObservableList<TableColumn<S,?>> columns = table.getColumns();

    if( includeHeaders )
    {
      html.beginRow();
      for( TableColumn<S,?> column : columns )
      {
        html.add( resolveColumnText(column) );
        int count = counts.get(column).intValue();
        for(int i = 1; i < count; i++)
          html.add("");
      }
      html.endRow();
    }

    int numRows = table.getItems().size();
    for( int i = 0; i < numRows; i++ )
    {
      html.beginRow();

      for( TableColumn<S,?> column : columns )
      {
        final List<String> datas = provider.provideCellData(data, column, i); /** @todo MJM handle markdown */
        appendCellDataHTML(html, counts, column, datas);
      }

      html.endRow();
    }

    return html.conclude();
  }

  private static <S> void appendCellDataHTML(HTMLTableHelper html,
                                             Map<TableColumn<S, ?>, Integer> counts, TableColumn<S, ?> column, final List<String> datas)
  {
    for(String datum : datas)
      html.add(datum); /** @todo MJM handle markdown */
    int count = counts.get(column).intValue();
    for(int j = datas.size(); j < count; j++)
      html.add("");
  }

  public static <S, ST> List<MenuItem> provideImageCaptureMenuItems(Node node, PrintImageHandler printHandler)
  {
    List<AbstractJFXAction<Node>> actions = new ArrayList<>(3);

    actions.add(new CopyImageAction());
    actions.add(new SaveImageAction());
    actions.add(new PrintImageAction(printHandler));

    ArrayList<MenuItem> items = new ArrayList<>(actions.size());
    for(AbstractJFXAction<Node> action : actions)
    {
      items.add(action.wrapInMenuItem(node));
    }

    return items;
  }

  public static void copyNodeToClipboardAsImage(Node node)
  {
    WritableImage snapshot = JFXImageUtil.takeSnapshot(node);

    final ClipboardContent content = new ClipboardContent();
    content.putImage(snapshot);
    Clipboard.getSystemClipboard().setContent(content);
  }
}
