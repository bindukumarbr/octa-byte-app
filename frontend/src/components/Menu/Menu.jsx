import { bool } from 'prop-types';
import { StyledMenu } from './Menu.styled';
import {
  Link
} from "react-router-dom";

const Menu = ({ open, ...props }) => {

  // Links are only keyboard-focusable while the menu is open.
  const tabIndex = open ? 0 : -1;

  return (
    <StyledMenu open={open} aria-hidden={!open} {...props}>
      <div>
        <nav>
          <ul>
            <li>
              <Link to="/" tabIndex = {tabIndex} style = {{outline:"none",border:"none"}}><div style={{paddingBottom : "2em", float:"left"}}><span aria-hidden="true">🏠</span> Home</div></Link>
            </li>
            <li>
              <Link to="/db" tabIndex = {tabIndex} style = {{outline:"none",border:"none"}}><div style={{paddingBottom : "2em", float:"left"}}><span aria-hidden="true">📋</span> DB Demo</div></Link>
            </li>
          </ul>
        </nav>
      </div>
    </StyledMenu>
  );
}

Menu.propTypes = {
  open: bool.isRequired,
}

export default Menu;