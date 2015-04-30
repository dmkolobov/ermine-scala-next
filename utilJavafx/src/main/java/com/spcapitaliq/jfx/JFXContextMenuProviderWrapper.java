package com.spcapitaliq.jfx;

import java.util.List;

import javafx.scene.Node;
import javafx.scene.control.MenuItem;
import javafx.scene.control.TableView;

import com.spcapitaliq.jfx.action.PrintImageHandler;
import com.spcapitaliq.jfx.table.TableViewDataProvider;

/**
 * Wrap the provider. Allows customization on top on an existing
 * JFXContextMenuProvider instance.
 *
 * @author mmorton
 */
public abstract class JFXContextMenuProviderWrapper implements JFXContextMenuProvider
{
  protected final JFXContextMenuProvider _provider;

  public JFXContextMenuProviderWrapper( JFXContextMenuProvider provider )
  {
    _provider = provider;
  }

  @Override
  public List<MenuItem> provideContextMenuItems(final Node node)
  {
    return _provider.provideContextMenuItems(node);
  }

  @Override
  public <S, ST> List<MenuItem> provideTableContextMenuItems(final TableView<S> table, final TableViewDataProvider<S, ST> provider)
  {
    return _provider.provideTableContextMenuItems(table, provider);
  }

  @Override
  public PrintImageHandler providePrintImageHandler()
  {
    return _provider.providePrintImageHandler();
  }
}
