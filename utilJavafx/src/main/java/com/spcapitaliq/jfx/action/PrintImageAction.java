package com.spcapitaliq.jfx.action;

import java.awt.print.*;
import javax.swing.SwingUtilities;

import javafx.event.ActionEvent;
import javafx.event.EventHandler;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.control.Button;
import javafx.scene.control.ButtonBuilder;
import javafx.scene.layout.HBoxBuilder;

import org.apache.log4j.Logger;

import com.spcapitaliq.jfx.concurrency.BlockerTask;
import com.spcapitaliq.jfx.concurrency.BlockerWrap;
import com.spcapitaliq.jfx.dialog.DialogControl;
import com.spcapitaliq.jfx.dialog.DialogFactory;
import com.spcapitaliq.jfx.image.JFXImageUtil;

/**
 *
 * @author mmorton
 *
 */
public class PrintImageAction extends AbstractJFXAction<Node>
{
  public static class DefactoPrintHandler implements PrintImageHandler
  {
    @Override
    public void handlePrint(ActionEvent ae, Node node)
    {
      PrintSetupDialog.show(node);
    }
  }

  private static final Logger Log = Logger.getLogger(PrintImageAction.class);

  private final PrintImageHandler _handler;

  public PrintImageAction()
  {
    this(new DefactoPrintHandler());
  }

  public PrintImageAction(PrintImageHandler handler)
  {
    _handler = handler;
  }

  @Override
  protected void handle(final ActionEvent ae, final Node node)
  {
    try
    {
      _handler.handlePrint(ae, node);
    }
    catch(Exception e)
    {
      Log.error("Failed to handlePrint", e);
    }
  }

  @Override
  protected String defineActionText()
  {
    return "Print...";
  }

  /**
   * Simple dialog with a button to launch page setup and print.
   *
   * @author mmorton
   */
  public static class PrintSetupDialog
  {
    private final PrinterJob _printJob;
    private PageFormat _printFormat;
    private final Node _parent;
    private final DialogControl _control;
    private final BlockerWrap _blocker;

    private PrintSetupDialog(Node parent, DialogControl control)
    {
      _parent = parent;
      _control = control;
      _printJob = PrinterJob.getPrinterJob();
      _printFormat = _printJob.defaultPage();
      _blocker = new BlockerWrap();
    }

    private Parent buildBody()
    {
      Parent body = HBoxBuilder.create()
        .children(
          ButtonBuilder.create()
            .text("Page Layout...")
            .onAction(new PrintSetupAction())
            .build(),
          ButtonBuilder.create()
            .text("Print...")
            .onAction(new PrintAction())
            .build()
        )
        .build();
      _blocker.pokeContent(body);

      Button bCancel = ButtonBuilder.create()
        .text("Cancel")
        .onAction(_control.buildSimpleCloseAction())
        .build();

      return DialogFactory.buildBodyWithConsole(_blocker.peekNode(), bCancel);
    }

    private class PrintSetupAction implements EventHandler<ActionEvent>
    {
      @Override
      public void handle(final ActionEvent ae)
      {
        SwingUtilities.invokeLater(new Runnable()
        {
          @Override
          public void run()
          {
            _printFormat = _printJob.pageDialog(_printFormat);
            _control.toFront();
          }
        });
      }
    }

    private class PrintAction implements EventHandler<ActionEvent>
    {
      @Override
      public void handle(final ActionEvent ae)
      {
        _blocker.bindTo(new Logic());
      }

      private class Logic extends BlockerTask<Object>
      {
        private boolean _canceled;

        @Override
        protected Object call() throws Exception
        {
          updateMessage("Configuring...");
          SwingUtilities.invokeAndWait(new Runnable() {
            @Override
            public void run()
            {
              _canceled = !_printJob.printDialog();
            }
          });

          if(!_canceled)
          {
            updateMessage("Printing...");
            try
            {
              Book book = new Book();
              Printable p = new JFXImageUtil.PrintableNode(_parent);
              book.append(p, _printFormat);
              _printJob.setPageable(book);
              _printJob.print();
              Log.info("Finished printing.");
              _control.close();
              DialogFactory.showInfo(_parent, "Successfully sent to printer.");
            }
            catch (Exception p)
            {
              DialogFactory.showError(_parent, "Failed to print.");
              Log.error("Failed to print", p);
            }
          }
          else
          {
            _control.toFront();
          }
          return null;
        }
      }
    }

    public static void show(Node nodeToPrint)
    {
      DialogControl control = new DialogControl(nodeToPrint);
      PrintSetupDialog dlg = new PrintSetupDialog(nodeToPrint, control);
      DialogFactory.showAny(control, "Print Setup", dlg.buildBody());
    }
  }
}
